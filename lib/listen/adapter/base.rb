require 'listen/options'

module Listen
  module Adapter
    class Base
      attr_reader :options

      # TODO: only used by tests
      DEFAULTS = {}

      def initialize(opts)
        @configured = nil
        options = opts.dup
        @mq = options.delete(:mq)
        @directories = options.delete(:directories)

        Array(@directories).each do |dir|
          next if dir.is_a?(Pathname)
          fail ArgumentError, "not a Pathname: #{dir.inspect}"
        end

        # TODO: actually use this in every adapter
        @recursion = options.delete(:recursion)
        @recursion = true if @recursion.nil?

        defaults = self.class.const_get('DEFAULTS')
        @options = Listen::Options.new(options, defaults)
      rescue
        _log_exception 'adapter config failed: %s:%s called from: %s', caller
        raise
      end

      # TODO: it's a separate method as a temporary workaround for tests
      def configure
        return if @configured
        @configured = true

        @callbacks ||= {}
        @directories.each do |dir|
          unless dir.is_a?(Pathname)
            fail ArgumentError, "not a Pathname: #{dir.inspect}"
          end

          callback = @callbacks[dir] || lambda do |event|
            _process_event(dir, event)
          end
          @callbacks[dir] = callback
          _configure(dir, &callback)
        end
      end

      def start
        configure
        calling_stack = caller.dup
        Listen::Internals::ThreadPool.add do
          begin
            _run
          rescue
            msg = "run() in thread failed: %s:\n"\
              " %s\n\ncalled from:\n %s", calling_stack

            _log_exception(msg)
            raise
          end
        end
      end

      def self.local_fs?
        true
      end

      def self.usable?
        const_get('OS_REGEXP') =~ RbConfig::CONFIG['target_os']
      end

      private

      def _queue_change(type, dir, rel_path, options)
        # TODO: temporary workaround to remove dependency on Change
        @mq.send(:_queue_raw_change, type, dir, rel_path, options)
      end

      def _log(*args, &block)
        self.class.send(:_log, *args, &block)
      end

      def _log_exception(msg, caller_stack)
        _log :error, format(
          msg,
          $ERROR_INFO,
          $ERROR_POSITION * "\n",
          caller_stack * "\n"
        )
      end

      def self._log(*args, &block)
        if block
          Listen::Logger.send(*args, block.call)
        else
          Listen::Logger.send(*args)
        end
      end
    end
  end
end
