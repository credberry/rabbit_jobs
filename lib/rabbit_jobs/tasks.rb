# require 'resque/tasks'
# will give you the resque tasks

require 'rabbit_jobs'
require 'logger'

namespace :rj do
  def initialize_rj_daemon(daemon)
    daemon.pidfile = ENV['PIDFILE']
    daemon.background = %w(yes true).include? ENV['BACKGROUND']
    RJ.logger = ::Logger.new(ENV['LOGFILE'] || $stdout)
    RJ.logger.level = ENV['VERBOSE'] ? Logger::INFO : Logger::WARN

    daemon
  end

  desc "Start a Rabbit Jobs worker"
  task :worker => :environment do
    require 'rabbit_jobs'

    queues = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split(',')
    worker = initialize_rj_daemon(RJ::Worker.new(*queues))

    exit(0) if worker.work
  end

  desc "Start a Rabbit Jobs scheduler"
  task :scheduler => :environment do
    scheduler = initialize_rj_daemon(RabbitJobs::Scheduler.new)

    scheduler.work
  end

  # Preload app files if this is Rails
  task :environment do
    if defined?(Rails) && Rails.respond_to?(:application)
      # Rails 3
      # Rails.application.eager_load!
      Rails.application.require_environment!
    elsif defined?(Rails::Initializer)
      # Rails 2.3
      $rails_rake_task = false
      Rails::Initializer.run :load_application_classes
    end
  end
end