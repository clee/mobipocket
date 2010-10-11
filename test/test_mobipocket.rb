require 'helper'

class Mobipocket::Tests::Unpack < Test::Unit::TestCase
  def test_number_of_records
    mobi = Mobipocket::Unpack.new("test/fixtures/mobi/Doctorow - I, Robot.mobi")
    assert_equal(33, mobi.records.length)
  end
end
