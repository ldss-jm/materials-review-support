require_relative '../sersol.rb'


RSpec.describe SersolEntry do

  describe 'blacklisted?' do

    ss1 = SersolEntry.new('include/exclude' => 'exclude')
    it 'true for records to be excluded' do
      expect(ss1.blacklisted?).to be true
    end

    ss2 = SersolEntry.new('include/exclude' => '')
    it 'raises error if whitelist not yes/no' do
      expect{ss2.blacklisted?}.to raise_error(RuntimeError)
    end
  end

  describe 'enddate' do

    date1 = Date.strptime('1/1/2017', '%m/%d/%Y')
    date2 = Date.strptime('9/20/2017', '%m/%d/%Y')

    ss1 = SersolEntry.new('enddate' => '2017')
    it 'returns Date object for yyyy dates' do
      expect(ss1.enddate).to eq(date1)
    end

    ss2 = SersolEntry.new('enddate' => '9/20/2017')
    it 'returns Date object for mm/dd/yyyy dates' do
      expect(ss2.enddate).to eq(date2)
    end

    it 'parses seasons (e.g. Fall) into dates' do
      expect(ss2.enddate).to eq(date2)
    end

    ss3 = SersolEntry.new('enddate' => 'august')
    it 'includes error note and original value on failure' do
      expect(ss3.enddate).to eq('error: august')
    end

  end

  describe 'end_mode' do

    ss1 = SersolEntry.new('enddate' => '', 'resource' => '')
    it 'is current when descriptor is empty' do
      expect(ss1.end_mode).to eq('current')
    end

    ss2 = SersolEntry.new('enddate' => 'CURRENT', 'resource' => '')
    it 'is current when downcased descriptor contains "current"' do
      expect(ss2.end_mode).to eq('current')
    end

    ss3 = SersolEntry.new('enddate' => '1 year ago', 'resource' => '')
    it 'is embargo when descriptor contains "ago"' do
      expect(ss3.end_mode).to eq('embargo')
    end

    ss4 = SersolEntry.new('enddate' => '2015', 'resource' => 'jstor')
    it 'is embargo when downcased descriptor contains "jstor"' do
      expect(ss4.end_mode).to eq('embargo')
    end

    ss5 = SersolEntry.new('enddate' => '2015', 'resource' => '')
    it 'is fixed when not current/embargo' do
      expect(ss5.end_mode).to eq('fixed')
    end
  end

  describe 'embargo_text' do

    ss1 = SersolEntry.new('enddate' => '2015', 'resource' => 'jstor')
    it 'operates BASED ON 2019 AS CURRENT YEAR' do
      expect(ss1.embargo_text).to eq('4 years ago')
    end
    it 'converts embargo fixed dates to relative dates' do
      expect(ss1.embargo_text).to match(/ago/)
    end
    it 'describes embargo enddates in 2015 as 4 years ago' do
      expect(ss1.embargo_text).to eq('4 years ago')
    end

    ss2 = SersolEntry.new('enddate' => '1 year ago')
    it 'does not modify enddates that are already relative' do
      expect(ss2.embargo_text).to eq('1 year ago')
    end
  end

  describe 'embargo_comparator' do

    today = Date.today

    ss1 = SersolEntry.new('enddate' => '9/20/2017', 'resource' => 'jstor')
    date = Date.strptime('9/20/2017', '%m/%d/%Y')
    it 'returns enddate when descriptor lacks ago' do
      expect(ss1.embargo_comparator).to eq(date)
    end

    ss2 = SersolEntry.new('enddate' => '1 year ago')
    it 'says 1 year ago was the date 365 days ago' do
      expect(ss2.embargo_comparator).to eq(today-365)
    end

    ss3 = SersolEntry.new('enddate' => '10 months ago')
    it 'counts months as 30 days' do
      expect(ss3.embargo_comparator).to eq(today-300)
    end

    ss4 = SersolEntry.new('enddate' => '4 weeks ago')
    it 'counts weeks as 7 days' do
      expect(ss4.embargo_comparator).to eq(today-28)
    end

    ss5 = SersolEntry.new('enddate' => '15 days ago')
    it 'counts days as...days' do
      expect(ss5.embargo_comparator).to eq(today-15)
    end
  end
end


RSpec.describe SersolTitle do

  sst1 = SersolTitle.new('1')
  ssc = SersolEntry.new('enddate' => '')
  sse = SersolEntry.new('enddate' => '1 year ago')
  ssf = SersolEntry.new('enddate' => '2000', 'resource' => '')
  sst1.entries = [ssc, sse, ssf]
  sst2 = SersolTitle.new('2')


  describe 'current' do
    it 'returns current access points' do
      expect(sst1.current).to eq([ssc])
    end

    it 'is nil if none exist' do
      expect(sst2.current).to be_nil
    end
  end

  describe 'embargo' do
    it 'returns embargo access points' do
      expect(sst1.embargo).to eq([sse])
    end

    it 'is nil if none exist' do
      expect(sst2.embargo).to be_nil
    end
  end

  describe 'fixed' do
    it 'returns fixed access points' do
      expect(sst1.fixed).to eq([ssf])
    end

    it 'is nil if none exist' do
      expect(sst2.fixed).to be_nil
    end
  end


  describe 'most_recent' do
    ssc2 = SersolEntry.new('enddate' => '')
    sse2 = SersolEntry.new('enddate' => '1 year ago')
    sse3 = SersolEntry.new('enddate' => '2 years ago')
    sse4 = SersolEntry.new('enddate' => '5000 years ago')
    ssf2 = SersolEntry.new('enddate' => '2000', 'resource' => '')
    ssf3 = SersolEntry.new('enddate' => '1999', 'resource' => '')

    sst3 = SersolTitle.new('3')
    sst3.entries = [ssc, ssc2, sse, sse2, sse3, sse4, ssf, ssf2, ssf3]
    it 'returns all current entries when they exist' do
      expect(sst3.most_recent).to eq([ssc, ssc2])
    end

    sst4 = SersolTitle.new('4')
    sst4.entries = [sse, sse2, sse3, sse4, ssf, ssf2, ssf3]
    it 'returns the embargo points with the shortest embargo if no current' do
      expect(sst4.most_recent).to eq([sse, sse2])
    end

    sst5 = SersolTitle.new('5')
    sst5.entries = [sse4, ssf, ssf2, ssf3]
    it 'always favors embargo over fixed' do
      expect(sst5.most_recent).to eq([sse4])
    end

    sst6 = SersolTitle.new('6')
    sst6.entries = [ssf, ssf2, ssf3]
    it 'returns the most recent fixed date points if no current/embargo' do
      expect(sst6.most_recent).to eq([ssf, ssf2])
    end
  end

  describe 'all_issns' do
  end

end
