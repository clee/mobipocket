class Mobipocket::Unpack
  # An array containing the record data from the ebook
  attr_accessor :records
  Record = Struct.new(:offset, :id, :data)
  Mobi = Struct.new(:title, :author, :numberOfBookRecords, :firstImageRecordIndex)

  def initialize(mobi_path = nil)
    @records = []
    load_from_path(mobi_path)
    self
  end


  protected
    def load_from_path(mobi_path)
      mobifile = open(mobi_path, 'rb')

      @records = parse_records(mobifile)
      @mobi = parse_mobi(@records[0])
      bookData = ''
      for recordIndex in 1..(@mobi.numberOfBookRecords)
        puts "record[#{recordIndex}] size is #{@records[recordIndex][:data].length}"
        bookData += @records[recordIndex][:data]
      end

      File.open("#{mobi_path}-test.raw", 'wb') {|f| f.write(bookData) }
    end

    def parse_records(mobifile)
      # FIXME: This is a hack, but it works. We should read all of 
      # the fields, not just this one.
      mobifile.seek(76, IO::SEEK_SET) 
      (numberOfRecords, ) = mobifile.read(2).unpack('n')

      numberOfRecords.times do
        (offset, attrib, uniqueID) = mobifile.read(8).unpack('N B8 B24')
        uniqueID = uniqueID.to_i(2)
        records << Record.new(offset, uniqueID, nil)
      end

      for recordIndex in 0..(numberOfRecords - 2)
        currentRecord = records.at(recordIndex)
        nextRecordOffset = records.at(recordIndex + 1).offset
        recordLength = nextRecordOffset - currentRecord.offset
        mobifile.seek(currentRecord.offset, IO::SEEK_SET)
        currentRecord[:data] = mobifile.read(recordLength)
      end

      records
    end

    def parse_mobi(record)
      (compressionType, unused, uncompressedTextLength, recordCount, recordSize, encryptionType, ) = record[:data][0,16].unpack('n n N n n n n')
      puts "Compression type: #{compressionType}"
      puts "Uncompressed length: #{uncompressedTextLength}"
      puts "record count/size: #{recordCount}/#{recordSize}"
      (mobiID, headerLength, mobiType, textEncoding, uniqueID, generatorVersion) = record[:data][16,24].unpack('N N N N N N')
      puts "Header length: #{headerLength}"

      (fullTitlePos, fullTitleLength) = record[:data][84,8].unpack('N N')
      fullTitle = record[:data][fullTitlePos,fullTitleLength].unpack('a*')
      puts "Full title: #{fullTitle} (pos/len: #{fullTitlePos}/#{fullTitleLength})"

      (extendedHeaderFlags, ) = record[:data][128,4].unpack('B8')
      if extendedHeaderFlags.to_i(2) & 0x40
        puts "Extended header detected (and r0 length is #{record[:data].length})"
      end
      firstImageRecord = record[:data][108,4].unpack('N')
      metadata = {}
      metadata.update(parse_exth(record[:data][(16+headerLength)..-1]))

      Mobi.new(fullTitle, 'Sample', recordCount, firstImageRecord)
    end

    def parse_exth(exth)
      (identifier, headerLength, recordCount) = exth[0,12].unpack('a4 N N')

      properties = {}
      puts "id, len, record count #{identifier} #{headerLength} #{recordCount}"
      pos = 12
      for i in 0..(recordCount - 1)
        (recordType, recordLength) = exth[pos,8].unpack('N N')
        pos = pos + recordLength
        recordValue = exth[pos-(recordLength - 8),recordLength-8].unpack('a*')
        puts "record type #{recordType} value #{recordValue}"
        properties[recordType] = recordValue
      end
      return properties
    end
end