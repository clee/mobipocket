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
        bookData += @records[recordIndex][:data]
      end

      File.open('/tmp/test.raw', 'w') {|f| f.write(bookData) }
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
      (compressionType, unused, uncompressedTextLength, recordCount, recordSize, encryptionType, ) = record[:data][0,16].unpack('nnNnnnn')
      puts "Compression type: #{compressionType}"
      puts "Uncompressed length: #{uncompressedTextLength}"
      puts "record count/size: #{recordCount}/#{recordSize}"
      (mobiID, headerLength, mobiType, textEncoding, uniqueID, generatorVersion) = record[:data][16,24].unpack('N N N N N N')
      puts "Header length: #{headerLength}"

      (fullTitlePos, fullTitleLength) = record[:data][84,8].unpack('N N')
      fullTitle = record[:data][fullTitlePos,fullTitleLength].unpack('a*')
      puts "Full title: #{fullTitle} (pos/len: #{fullTitlePos}/#{fullTitleLength})"

      (extendedHeaderFlags, ) = record[:data][128..131].unpack('B8')
      if extendedHeaderFlags.to_i(2) & 0x40
        puts "Extended header detected (and r0 length is #{record[:data].length})"
      end
      firstImageRecord = record[:data][108,4].unpack('N')

      Mobi.new(fullTitle, 'Sample', recordCount, firstImageRecord)
    end
end