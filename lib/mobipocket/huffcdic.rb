#!/usr/bin/env ruby

require 'enumerator'

class Mobipocket::Huffcdic
  attr_reader :mincode, :maxcode, :predictionary, :dict1
  attr_accessor :dictionary

  CDICEntry = Struct.new(:length, :expanded, :data)

  def initialize(huffRecords)
    raise ArgumentError, 'invalid list' unless huffRecords.respond_to?(:each)
    loadHuff(huffRecords[0][:data])

    if "\x01\x02\x03\x04\x05\x06\x07\x08".unpack("Q>")[0] == 0x0102030405060708
      alias get_64bit_int get_64bit_int_fast
    else
      alias get_64bit_int get_64bit_int_slow
    end

    @dictionary = []

    huffRecords[1..-1].each do |cdic|
      @dictionary.concat(loadCdic(cdic[:data]))
    end

    @predictionary = Marshal.load(Marshal.dump(@dictionary))

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

    dict2 = huff[off2,0x100].unpack('N64').insert(0, 0, 0)
    @mincode, @maxcode, codelen = [], [], 0
    dict2.each_slice(2) do |currentMinCode, currentMaxCode|
      @mincode << (currentMinCode << (32 - codelen))
      @maxcode << ((currentMaxCode + 1) << (32 - codelen)) - 1
      codelen += 1
    end
  end

  def loadCdic(cdic, n=nil)
    raise ArgumentError, 'Invalid CDIC header' if cdic[0,8] != "CDIC\0\0\0\x10"

    phrases, bits = cdic[8,8].unpack('N N')
    n = n || [phrases - @dictionary.length, 1 << bits].min

    return cdic[0x10,n*2].unpack("n#{n}").collect do |off|
      flaggedLength, = cdic[off+0x10,2].unpack('n')
      expanded = flaggedLength & 0x8000 == 0x8000
      length = flaggedLength & 0x7FFF
      CDICEntry.new(length, expanded, cdic[off+0x12,length])
    end
  end

  def unpack(data)
    output = ''
    bitsleft = data.length * 8
    data << "\0\0\0\0\0\0\0\0"
    position = 0
    x = get_64bit_int(data[position,8])
    n = 32

    while true
      if n <= 0
        position += 4
        x = get_64bit_int(data[position,8])
        n += 32
      end
      code = (x >> n) & 0xFFFF_FFFF

      codelen, term, maxcode = @dict1[code >> 24]
      if term == 0
        codelen += 1 while code < @mincode[codelen]
        maxcode = @maxcode[codelen]
      end

      n -= codelen
      bitsleft -= codelen

      break if bitsleft < 0

      r = ((maxcode - code) >> (32 - codelen))
      chunk = @dictionary[r][:data]
      if not @dictionary[r][:expanded]
        @dictionary[r] = CDICEntry.new(0, true, '')
        chunk = unpack(chunk)
        @dictionary[r] = CDICEntry.new(chunk.length, true, chunk)
      end

      output << chunk
    end

    return output
  end

  def cdicsFrom(dictionary)
    offsets = [[]]
    cdics = ['']
    currentOffset = 0
    l = dictionary.length

    numberOfBits = 0
    numberOfBits += 1 while (l >>= 1) > 0

    dictionary.each do |c|
      raise ArgumentError, "data too long for cdic!" if c[:length] > 0x7FFF

      # offsets are 16-bit unsigned ints, so if we overflow, start a new cdic
      if currentOffset > 0xFFFF || (offsets.last.length == (1 << numberOfBits))
        currentOffset = 0
        cdics << ''
        offsets << []
      end

      offsets.last << currentOffset

      flaggedLength = c[:length]
      flaggedLength |= 0x8000 if c[:expanded]
      cdics.last << [flaggedLength].pack('n') << c[:data]

      currentOffset = currentOffset + 2 + c[:length]
    end

    r = []
    for index in 0..(cdics.length-1)
      o = offsets[index].collect do |originalOffset|
        originalOffset + (2 * offsets[index].length)
      end
      r[index] = (['CDIC', 0x10, dictionary.length, numberOfBits].pack('A4 N3') << o.pack("n#{o.length}") << cdics[index])
    end

    return r
  end

  private
  def get_64bit_int_slow(quad)
    return quad.unpack('B64')[0].to_i(2)
  end

  def get_64bit_int_fast(quad)
    return quad.unpack('Q>')[0]
  end
end
