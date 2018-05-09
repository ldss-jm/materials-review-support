require_relative '../class_nonsersol.rb'

RSpec.describe WileyEntry do
  
  data = {'title' => 'Abacus',
          'e-issn' => '1467-6281',
          'issn' => '0001-3072',
          'ssj#' => 'ssj0001878'}
  w = WileyEntry.new(data)

  describe 'initialize' do

    it 'sets record as original hash' do
      expect(w.record).to eq(data)
    end

    w2 = WileyEntry.new({'title' => 'Abacus',
                         'e-issn' => '1467-6281',
                         'issn' => '0001-3072',
                         'ssj#' => 'n/a'})

    it 'does not set ssj when incoming ssj# doesn\'t begin \'ss\'' do
      expect(w2.ssj).to be_nil
    end
  end
  
  describe 'all_issns' do
    it 'includes values from "issn" field' do
      expect(w.all_issns.include?('0001-3072')).to be true
    end

    it 'includes values from "e-issn" field' do
      expect(w.all_issns.include?('1467-6281')).to be true      
    end
  end
end
