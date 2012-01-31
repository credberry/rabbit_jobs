# -*- encoding : utf-8 -*-
require 'spec_helper'
require 'json'

describe RabbitJobs::Publisher do

  before(:each) do
    queue_name = 'test'
    RabbitJobs.configure do |c|
      c.exchange 'test'
      c.queue 'rspec_queue'
    end
  end

  it 'should publish message to queue' do
    RabbitJobs.enqueue(TestJob, 'some', 'other', 'params')
    RabbitJobs::Publisher.purge_queue('rspec_queue').should == 1
  end
end