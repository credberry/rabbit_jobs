# -*- encoding : utf-8 -*-

module RabbitJobs
  class Worker
    include MainLoop

    delegate :amqp_connection, :consumer_channel, :amqp_cleanup, to: RabbitJobs

    attr_accessor :process_name
    attr_reader :consumer

    def consumer=(value)
      raise ArgumentError.new("value=#{value.inspect}") unless value.respond_to?(:process_message)
      @consumer = value
    end

    def queue_params(routing_key)
      RJ.config[:queues][routing_key.to_sym]
    end

    # Workers should be initialized with an array of string queue
    # names. The order is important: a Worker will check the first
    # queue given for a job. If none is found, it will check the
    # second queue name given. If a job is found, it will be
    # processed. Upon completion, the Worker will again check the
    # first queue given, and so forth. In this way the queue list
    # passed to a Worker on startup defines the priorities of queues.
    #
    # If passed a single "*", this Worker will operate on all queues
    # in alphabetical order. Queues can be dynamically added or
    # removed without needing to restart workers using this method.
    def initialize(*queues)
      @queues = queues.map { |queue| queue.to_s.strip }.flatten.uniq
      if @queues == ['*'] || @queues.empty?
        @queues = RabbitJobs.config.routing_keys
      end
      raise "Cannot initialize worker without queues." if @queues.empty?
    end

    def queues
      @queues || []
    end

    # Subscribes to queue and working on jobs
    def work
      return false unless startup
      @consumer ||= RJ::Consumer::JobConsumer.new

      $0 = process_name || "rj_worker (#{queues.join(', ')})"

      @processed_count = 0

      begin
        consumer_channel.prefetch(1)

        queues.each do |routing_key|
          consume_queue(routing_key)
        end

        RJ.logger.info 'Started.'

        return main_loop do
          RJ.logger.info "Processed jobs: #{@processed_count}."
        end
      rescue
        log_daemon_error($ERROR_INFO)
      end

      true
    end

    def startup
      RJ._run_after_fork_callbacks

      $stdout.sync = true

      @shutdown = false

      Signal.trap('TERM') { shutdown }
      Signal.trap('INT')  { shutdown! }

      true
    end

    private

    def consume_message(delivery_info, properties, payload)
      if RJ.run_before_process_message_callbacks
        begin
          @consumer.process_message(delivery_info, properties, payload)
          @processed_count += 1
        rescue ScriptError, StandardError
          RabbitJobs.logger.error(
            short_message: $ERROR_INFO.message,
            _payload: payload,
            _exception: $ERROR_INFO.class,
            full_message: $ERROR_INFO.backtrace.join("\r\n"))
        end
        true
      else
        RJ.logger.warn "before_process_message hook failed, requeuing payload: #{payload.inspect}"
        false
      end
    end

    def consume_queue(routing_key)
      RJ.logger.info "Subscribing to #{routing_key}"
      routing_key = routing_key.to_sym

      queue = consumer_channel.queue(routing_key, queue_params(routing_key))

      explicit_ack = queue_params(routing_key)[:manual_ack].present?

      queue.subscribe(manual_ack: explicit_ack) do |delivery_info, properties, payload|
        if consume_message(delivery_info, properties, payload)
          consumer_channel.ack(delivery_info.delivery_tag) if explicit_ack
        else
          requeue = false
          consumer_channel.nack(delivery_info.delivery_tag, requeue) if explicit_ack
        end
      end
    end
  end
end
