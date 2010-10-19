#!/usr/bin/env ruby

class Mobipocket::PalmDoc  
  attr_accessor :unpacked

  def initialize
    return self
  end

  def unpack(data)
    output = ''
    position = 0
    while position < data.length
      currentByte = data[position].ord
      position += 1
      case currentByte
      when 0x00,0x09..0x7F then
        output << currentByte
      when 0x01..0x08 then
        output << data[position,currentByte]
        position += currentByte
      when 0xC0..0xFF then
        output << 0x20 << (currentByte ^ 0x80)
      when 0x80..0xBF then
        if !(position < data.length)
          raise IndexError
        end

        currentByte = ((currentByte << 8) | data[position].ord)
        position += 1
        distance = ((currentByte >> 3) & 0x07FF)
        length = ((currentByte & 0x07) + 3)
        if distance > length
          output << output[-distance,length]
        else
          length.times { output << output[-distance] }
        end
      end
    end
    return output
  end

  def pack(data)
    output = ''
    offset = 0

    while offset < data.length
      if (offset > 10) && (data.length - offset > 10)
        chunk = ''
        needle = -1
        preamble = data[0,offset]

        10.downto(3) { |haystack|
          chunk = data[offset,haystack]
          needle = preamble.rindex(chunk) || -1

          break if needle >= 0 && ((offset - needle) < 2048);
          needle = -1;
        }

        if (needle >= 0) && (chunk.length <= 10) && (chunk.length >= 3)
          distance = offset - needle
          output << [0x8000 + ((distance << 3) & 0x3FF8) + chunk.length - 3].pack('n')
          offset += chunk.length
          next
        end
      end

      currentChar = data[offset]
      offset += 1

      case currentChar
      when 0x20 then
        if offset + 1 < data.length
          nextChar = data[offset]
          if ((0x40..0x7F).include?(nextChar))
            output << (nextChar ^ 0x80)
            offset += 1
          else
            output << currentChar
          end
        end
      when 0x00,0x09..0x7F then
        output << currentChar
      else
        nextChunk = data[(offset-1)..-1]
        if nextChunk =~ /([\x01-\x08\x80-\xff]{1,8})/o
          literals = Regexp.last_match(1)
          output << literals.length
          output << literals
          offset += (literals.length - 1)
        end
      end
    end

    return output
  end
end