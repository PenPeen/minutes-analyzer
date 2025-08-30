require 'spec_helper'
require_relative '../lib/processing_statistics'

RSpec.describe ProcessingStatistics do
  let(:stats) { described_class.new }
  
  describe '#initialize' do
    it 'initializes with zero statistics' do
      initial_stats = stats.get_statistics
      
      expect(initial_stats[:total_processed]).to eq(0)
      expect(initial_stats[:successful]).to eq(0)
      expect(initial_stats[:failed]).to eq(0)
      expect(initial_stats[:success_rate]).to eq(0)
      expect(initial_stats[:average_processing_time]).to eq(0)
    end
  end
  
  describe '#record_success' do
    it 'records successful processing' do
      stats.record_success(1.5)
      
      result = stats.get_statistics
      expect(result[:total_processed]).to eq(1)
      expect(result[:successful]).to eq(1)
      expect(result[:failed]).to eq(0)
      expect(result[:success_rate]).to eq(100.0)
      expect(result[:average_processing_time]).to eq(1.5)
    end
  end
  
  describe '#record_failure' do
    it 'records failed processing' do
      stats.record_failure(2.0)
      
      result = stats.get_statistics
      expect(result[:total_processed]).to eq(1)
      expect(result[:successful]).to eq(0)
      expect(result[:failed]).to eq(1)
      expect(result[:success_rate]).to eq(0.0)
      expect(result[:average_processing_time]).to eq(2.0)
    end
  end
  
  describe 'mixed success and failure' do
    it 'calculates correct statistics' do
      stats.record_success(1.0)
      stats.record_success(2.0)
      stats.record_failure(3.0)
      
      result = stats.get_statistics
      expect(result[:total_processed]).to eq(3)
      expect(result[:successful]).to eq(2)
      expect(result[:failed]).to eq(1)
      expect(result[:success_rate]).to eq(66.67)
      expect(result[:average_processing_time]).to eq(2.0)
    end
  end
  
  describe '#send_metrics_to_cloudwatch' do
    it 'outputs metrics in JSON format' do
      stats.record_success(1.5)
      
      expect { stats.send_metrics_to_cloudwatch }.to output(/ProcessedTranscripts.*1/).to_stdout
    end
  end
  
  describe '#reset' do
    it 'resets all statistics to zero' do
      stats.record_success(1.0)
      stats.record_failure(2.0)
      
      stats.reset
      
      result = stats.get_statistics
      expect(result[:total_processed]).to eq(0)
      expect(result[:successful]).to eq(0)
      expect(result[:failed]).to eq(0)
    end
  end
end