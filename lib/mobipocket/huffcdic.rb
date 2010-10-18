#!/usr/bin/env ruby

require 'enumerator'

class Mobipocket::Unpack::Huffcdic
  attr_reader :unpacked, :mincode, :maxcode, :dictionary, :dict1

  def initialize(huff, cdics)
    @unpacked = ''
    loadHuff(huff)

    raise ArgumentError, 'cdics isn\'t a list' unless cdics.respond_to?(:each)
    cdics.each do |cdic|
        loadCdic(cdic)
    end

    return self
  end

  def loadHuff(huff)
    raise ArgumentError, 'Invalid HUFF header' if huff[0,8] != "HUFF\0\0\0\x18"

    off1, off2 = huff[8,8].unpack('N N')

    @dict1 = huff[off1,0x400].unpack('N256').collect do |v|
        codelen, term, maxcode = v & 0x1F, v & 0x80, v >> 8
        raise ArgumentError, "Invalid codelen in header!" if codelen == 0
        raise ArgumentError, "Invalid term in header!" if term == 0 && codelen <= 8
        maxcode = ((maxcode + 1) << (32 - codelen)) - 1
        [codelen, term, maxcode]
    end

    dict2 = huff[off2,0x200].unpack('N64').insert(0, 0, 0)
    @mincode, @maxcode, codelen = [], [], 0
    dict2.each_slice(2) do |currentMinCode, currentMaxCode|
        @mincode << (currentMinCode << (32 - codelen))
        @maxcode << ((currentMaxCode + 1) << (32 - codelen)) - 1
        codelen += 1
    end

    @dictionary = []
  end

  def loadCdic(cdic)
    raise ArgumentError, 'Invalid CDIC header' if cdic[0,8] != "CDIC\0\0\0\x10"

    phrases, bits = cdic[8,8].unpack('N N')
    n = [phrases - @dictionary.length, 1 << bits].min

    cdic[0x10,n*2].unpack("n#{n}").each do |off|
        blen, = cdic[off+0x10,2].unpack('n')
        @dictionary << [cdic[off+0x12,(blen & 0x7FFF)], blen & 0x8000]
    end
  end

  def unpack(data)
    output = ''
    bitsleft = data.length * 8
    data << "\0\0\0\0\0\0\0\0"
    position = 0
    x = data[position,8].unpack('B64')[0].to_i(2)
    n = 32

    while true
        if n <= 0
            position += 4
            x = data[position,8].unpack('B64')[0].to_i(2)
            n += 32
        end
        code = (x >> n) & ((1 << 32) - 1)

        codelen, term, maxcode = @dict1[code >> 24]
        if term == 0
            codelen += 1 while code < @mincode[codelen]
            maxcode = @maxcode[codelen]
        end

        n -= codelen
        bitsleft -= codelen

        break if bitsleft < 0

        r = ((maxcode - code) >> (32 - codelen))
        chunk, flag = @dictionary[r]
        if flag == 0
            @dictionary[r] = [nil, 1]
            chunk = unpack(chunk)
            @dictionary[r] = [chunk, 1]
        end
        output << chunk
    end

    return output
  end
end
