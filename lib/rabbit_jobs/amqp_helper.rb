# -*- encoding : utf-8 -*-
require 'bunny'
require 'uri'

module RabbitJobs
  class AmqpHelper

    class << self

      def prepare_connection
        conn = Bunny.new(RJ.config.server)
        conn.start unless conn.connected? || conn.connecting?
        conn
      end

    end
  end
end