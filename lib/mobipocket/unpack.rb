require 'mobipocket/huffcdic'
require 'mobipocket/palmdoc'
require 'enumerator'

class Mobipocket::Unpack
  # An array containing the record data from the ebook
  attr_accessor :records

  # A custom struct with some metadata
  attr_accessor :mobi

  # The decompressed string containing the book HTML
  attr_accessor :uncompressed

  attr_accessor :reader
  attr_accessor :metadata

  Record = Struct.new(:offset, :id, :data)
  Mobi = Struct.new(:title, :author, :numberOfBookRecords, :firstImageRecordIndex)

  def initialize(mobi_path = nil)
    @records = []
    load_from_path(mobi_path)

    @uncompressed = uncompressed_book_text()

    self
  end

  def uncompressed_book_text()
    book_records().collect do |record|
      data = record.data
      num = 0
      data[-4,4].unpack('C4').each do |byte|
        num = 0 if (byte & 0x80 == 0x80)
        num = (num << 7) | (byte & 0x7F)
      end
      data = data[0..-num]
      @reader.unpack(data)
    end
  end

  protected
    def load_from_path(mobi_path)
      mobifile = open(mobi_path, 'rb')

      @records = parse_records(mobifile)
      @mobi = parse_mobi(@records[0])
      bookData = ''
      for recordIndex in 1..(@mobi.numberOfBookRecords)
        bookData << @records[recordIndex][:data]
      end
    end

    def parse_records(mobifile)
      # FIXME: This is a hack, but it works. We should read all of
      # the fields, not just this one.
      mobifile.seek(0x4C, IO::SEEK_SET)
      (numberOfRecords,) = mobifile.read(2).unpack('n')

      numberOfRecords.times do
        (offset, attrib, uniqueID) = mobifile.read(8).unpack('N B8 B24')
        uniqueID = uniqueID.to_i(2)
        records << Record.new(offset, uniqueID, nil)
      end

      records.each_index do |recordIndex|
        currentRecord = records.at(recordIndex)
        if recordIndex < records.length - 1
          nextRecordOffset = records.at(recordIndex + 1).offset
        else
          mobifile.seek(0, IO::SEEK_END)
          nextRecordOffset = mobifile.pos
        end
        recordLength = nextRecordOffset - currentRecord.offset
        mobifile.seek(currentRecord.offset, IO::SEEK_SET)
        currentRecord[:data] = mobifile.read(recordLength)
      end

      return records
    end

    def parse_mobi(record)
      (compressionType, unused, uncompressedTextLength, recordCount, recordSize, encryptionType, ) = record[:data][0,16].unpack('n n N n n n n')
      puts "Compression type: #{compressionType}"

      @reader = nil
      case compressionType
      when 17480 then
        (huffoff, hufflen) = record[:data][112,8].unpack('N N')
        @reader = Mobipocket::Huffcdic.new(@records[huffoff,hufflen])
      when 2 then
        @reader = Mobipocket::PalmDoc.new
      else
        @reader = Class.new do def unpack(data) return data end; end.new
      end

      puts "Uncompressed length: #{uncompressedTextLength}"
      puts "record count/size: #{recordCount}/#{recordSize}"
      (mobiID, headerLength, mobiType, textEncoding, uniqueID, generatorVersion) = record[:data][16,24].unpack('N N N N N N')
      puts "Header length: #{headerLength}"

      (fullTitlePos, fullTitleLength) = record[:data][84,8].unpack('N N')
      (fullTitle,) = record[:data][fullTitlePos,fullTitleLength].unpack('a*')
      puts "Full title: #{fullTitle} (pos/len: #{fullTitlePos}/#{fullTitleLength})"

      (extendedHeaderFlags,) = record[:data][0x80,4].unpack('N')
      if extendedHeaderFlags & 0x40 == 0x40
        puts "Extended header #{extendedHeaderFlags} (r0 length is #{record[:data].length})"
        @metadata = parse_exth(record[:data][(16+headerLength)..-1])
        @metadata.each do |k, v|
          puts "\t#{k}: #{v}"
        end
      end
      (firstImageRecord,) = record[:data][108,4].unpack('N')

      Mobi.new(fullTitle, 'Sample', recordCount, firstImageRecord)
    end

    def parse_exth(exth)
      (identifier, headerLength, recordCount) = exth[0,12].unpack('a4 N N')
      puts "id/len/record count: #{identifier}/#{headerLength}/#{recordCount}"
      raise ArgumentError unless identifier == 'EXTH'

      properties = {}
      pos = 12

      recordCount.times do |i|
        (recordType, recordLength) = exth[pos,8].unpack('N N')
        pos = pos + recordLength
        (recordValue,) = exth[pos-(recordLength-8),recordLength-8].unpack('a*')
        (recordValue,) = recordValue.unpack("N") if recordValue.include? "\x00"
        properties[recordType] = recordValue
      end
      return properties
    end

    def book_records
      return @records[1,@mobi.numberOfBookRecords]
    end
end
