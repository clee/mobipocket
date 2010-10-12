#!/usr/bin/env ruby

class Mobipocket::Unpack::PalmDoc  
  attr_accessor :unpacked

  def initialize(input)
    @unpacked = unpack(input)
    return self
  end
  
  def unpack(data)
    o = ''
    p = 0
    while p < data.length
      c = data[p].ord
      p += 1
      if (c >= 1) && (c <= 8)
        o << data[p,c]
        p += c
      elsif c < 128
        o << c
      elsif c >= 192
        o << ' ' << (c ^ 128)
      else
        if p < data.length
          c = ((c << 8) | data[p].ord)
          p += 1
          m = ((c >> 3) & 0x07FF)
          n = ((c & 7) + 3)
          if m > n
            o << o[-m,n]
          else
            n.times { o << o[-m] }
          end
        end
      end
    end
    return o
  end
end