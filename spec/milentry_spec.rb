require_relative '../nonsersol.rb'
require_relative '../../worldcat_api_and_wcm/metadata_api.rb'

RSpec.describe MilEntry do
  let(:api) { MetadataAPI.new('../worldcat_api_and_wcm/kms.metadata.secret') }

  class MilEntry
    attr_reader :_022a, :_022L, :_022y, :_776
  end

  data = {'record #(order)' => 'o15841212',
          '245' => 'The daily advance',
          '001' => '13380767',
          '022|a' => '0000-022a',
          '022|l' => '0000-022La 0000-022Lb',
          '022|y' => '0000-022ya  0000-022yb',
          '776|x' => '0000-776xa;0000-776xb'}
  s = MilEntry.new(data)

  describe 'initialize' do
    it 'sets record as original hash' do
      expect(s.record).to eq(data)
    end

    it 'sets @title from 245' do
      expect(s.title).to eq('The daily advance')
    end

    it 'sets @_001 from 1' do
      expect(s._001).to eq('13380767')
    end

    it 'sets @_022[x] as array' do
      expect(s._022a).to be_an(Array)
    end

    it '@_022[x] set from space-delimited 022|[x] string' do
      expect(s._022L).to eq(['0000-022La', '0000-022Lb'])
    end

    it '@_022[x] contains no empty strings' do
      expect(s._022y.include?('') && s._022y.include?(' ')).to be false
    end

    it 'sets @_776 from ;-delimited 776|x string' do
      expect(s._776).to eq(['0000-776xa', '0000-776xb'])
    end

    it 'does not set @ssj when incoming ssj# doesn\'t begin \'ss\'' do
      expect(s.ssj).to be_nil
    end

    s2 = MilEntry.new('record #(order)' => 'o15841212',
                      '245' => 'The daily advance',
                      '1' => 'ss13380767',
                      '022|a' => '0000-022a',
                      '022|l' => '0000-022La 0000-022Lb',
                      '022|y' => '0000-022ya  0000-022yb',
                      '776|x' => '0000-776xa;0000-776xb')
    it 'sets @ssj when 001 begins \'ss\'' do
      expect(s2.ssj).to eq(s2._001)
    end

    it 'sets @ss_match new set' do
      expect(s.ss_match).to be_an(Set)
    end
  end

  describe 'gen_all_issns' do
    s.gen_all_issns
    it 'sets all_issns as a set' do
      expect(s.all_issns).to be_an(Set)
    end

    it 'includes issns in 022a' do
      expect(s.all_issns.include?('0000-022a')).to be true
    end

    it 'includes issns in 022L' do
      expect(s.all_issns.include?('0000-022La')).to be true
    end

    it 'does not include issns in 022y' do
      expect(s.all_issns.include?('0000-022ya')).to be false
    end
  end

  describe 'add_022y' do
  end

  describe 'add_scraped_issns' do
    'includes scraped issns when present'
  end

  describe 'scrape_issns' do
    data3 = {
      'record #(order)' => 'o15841212',
      '245' => 'The daily advance',
      '001' => '812282',
      '022|a' => '0000-022a',
      '022|l' => '0000-022La 0000-022Lb',
      '022|y' => '0000-022ya  0000-022yb',
      '776|x' => '0000-776xa 0000-776xb'
    }
    s3 = MilEntry.new(data3)

    it 'returns issns that match the 001' do
      s3.scrape_issns(api)
      expect(s3.scraped_issns.include?('0033-1457')).to be true
    end
  end
end
