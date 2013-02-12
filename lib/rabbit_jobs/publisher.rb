# -*- encoding : utf-8 -*-

require 'json'
require 'amqp'
require 'eventmachine'
require 'uri'

module RabbitJobs
  module Publisher
    extend self

    def publish(klass, *params, &block)
      publish_to(RJ.config.default_queue, klass, *params, &block)
    end

    def publish_to(routing_key, klass, *params, &block)
      raise ArgumentError.new("klass=#{klass.inspect}") unless klass && (klass.is_a?(Class) || klass.is_a?(String))
      raise ArgumentError.new("routing_key=#{routing_key}") unless routing_key && (routing_key.is_a?(Symbol) || routing_key.is_a?(String)) && !!RJ.config[:queues][routing_key.to_s]

      payload = {
        'class' => klass.to_s,
        'opts' => {'created_at' => Time.now.to_i},
        'params' => params
        }.to_json

      direct_publish_to(RJ.config.queue_name(routing_key.to_s), payload, &block)
    end

    def direct_publish_to(routing_key, payload, ex = {}, &block)
      ex = {name: ex} if ex.is_a?(String)
      raise ArgumentError.new("Need to pass exchange name") if ex.size > 0 && ex[:name].to_s.empty?

      begin
        AmqpHelper.prepare_channel

        if ex.size > 0
          AMQP::Exchange.new(AMQP.channel, :direct, ex[:name].to_s, Configuration::DEFAULT_EXCHANGE_PARAMS.merge(ex[:params] || {})) do |exchange|
            exchange.publish(payload, Configuration::DEFAULT_MESSAGE_PARAMS.merge({key: routing_key.to_s})) do
              yield if block_given?
            end
          end
        else
          AMQP.channel.default_exchange.publish(payload, Configuration::DEFAULT_MESSAGE_PARAMS.merge({key: routing_key.to_s})) do
            yield if block_given?
          end
        end
      rescue
        RJ.logger.warn $!.message
        RJ.logger.warn $!.backtrace.join("\n")
        raise $!
      end

      true
    end

    def purge_queue(*routing_keys, &block)
      raise ArgumentError unless routing_keys && routing_keys.count > 0

      messages_count = 0
      count = routing_keys.count

      AmqpHelper.prepare_channel

      routing_keys.each do |routing_key|
        queue = AMQP.channel.queue(RJ.config.queue_name(routing_key), RJ.config[:queues][routing_key.to_s])
        queue.status do |messages, consumers|
          # messages_count += messages
          queue.purge do |ret|
            raise "Cannot purge queue #{routing_key.to_s}." unless ret.is_a?(AMQ::Protocol::Queue::PurgeOk)
            messages_count += ret.message_count
            count -= 1
            if count == 0
              yield messages_count if block_given?
            end
          end
        end
      end
    end
  end
end