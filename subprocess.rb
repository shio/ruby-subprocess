#!/usr/local/bin/ruby

class Subprocess
  class Error < StandardError
  end

  class CalledProcessError < Error
    attr_accessor :exit_status
  end

  PIPE = :PIPE
  STDOUT = :STDOUT

  attr_reader :pid
  attr_reader :status
  attr_reader :stdin, :stdout, :stderr

  def initialize(args, options={})
    @args, @options = args, options
    @bufsize            = @options[:bufsize] || 0
    @executable         = @options[:executable]
    @preexec_fn         = @options[:preexec_fn]
    @close_fds          = @options[:close_fds]
    @shell              = @options[:shell]
    @cwd                = @options[:cwd]
    @env                = @options[:env]
    @universal_newlines = @options[:universal_newlines]
    @startupinfo        = @options[:startupinfo]
    @creationflags      = @options[:creationflags] || 0
  end

  def self.start(args, options={})
    raise ArgumentError unless block_given?
    s = self.new(args, options).run
    yield s
    s.wait unless s.status
  end

  def execute
    case @args
    when String
      command, args = @args, []
    when Array
      args = @args.dup
      command = args.shift
      if @options[:executable]
        if command.is_a?(String)
          command = [@options[:executable], @args.first]
        else
          raise ArgumentError, "Invalid args for exec: %s" % @args.inspect
        end
      end
    else
      raise ArgumentError, "Invalid arguments for exec: %s" % @args.inspect
    end
    Process.exec(command, *args)
  end

  def run
    ::STDOUT.flush
    ::STDERR.flush

    case @options[:stdin]
    when :PIPE, IO
      pipe_in = IO::pipe
    end
    case @options[:stdout]
    when :PIPE, IO
      pipe_out = IO::pipe
    end
    case @options[:stderr]
    when :PIPE, IO
      pipe_err = IO::pipe
    end

    @pid = Process.fork {
      case @options[:stdin]
      when :PIPE, IO
        pipe_in.last.close
        ::STDIN.reopen(pipe_in.first)
        pipe_in.first.close
      end
      case @options[:stdout]
      when :PIPE, IO
        pipe_out.first.close
        ::STDOUT.reopen(pipe_out.last)
        pipe_out.last.close
      end
      case @options[:stderr]
      when :PIPE, IO
        pipe_err.first.close
        ::STDERR.reopen(pipe_err.last)
        pipe_err.last.close
      when :STDOUT
        ::STDERR.reopen(::STDOUT)
      end
      begin
        execute
      ensure
        exit!
      end
    }

    case input = @options[:stdin]
    when :PIPE, IO
      pipe_in.first.close
      @stdin = pipe_in.last
      @input = input if input.is_a?(IO)
    end
    case output = @options[:stdout]
    when :PIPE, IO
      pipe_out.last.close
      @stdout = pipe_out.first
      @output = output if output.is_a?(IO)
    end
    case errput = @options[:stderr]
    when :PIPE, IO
      pipe_err.last.close
      @stderr = pipe_err.first
      @errput = errput if errput.is_a?(IO)
    end

    self
  end

  def poll
    if r = Process.waitpid2(@pid, Process::WNOHANG)
      _, @status = r
      @status
    else
      nil
    end
  end

  def wait
    _, @status = Process.waitpid2(@pid)
    @status
  end

  def send_signal(signal)
    Process.kill(signal, @pid)
  end
  def terminate
    send_signal(:TERM)
  end
  def kill
    send_signal(:KILL)
  end

  def communicate_simple(input)
    if @stdin
      if @input.is_a?(IO)
        input = @input.read
      end
      @stdin.write(input) if input
      @stdin.close
    else
      raise ArgumentError, "Specify :stdin with input" if @input or input
    end
    if @output
      stdout_data = nil
      @output.write @stdout.read
      @output.flush
    else
      stdout_data = @stdout.read
    end
    if @errput
      stderr_data = nil
      @errput.write @stderr.read
      @errput.flush
    else
      stderr_data = (@stderr) ? @stderr.read : nil
    end
    @stdout.close
    @stderr.close if @stderr
    return stdout_data, stderr_data
  end

  def communicate(input=nil)
    run
    # XXX fix I/O
    stdout_data, stderr_data = communicate_simple(input)
    wait
    return stdout_data, stderr_data
  end


  def self.call(args, options={})
    self.new(args, options).run.wait
  end

  def self.check_call(args, options={})
    status = self.new(args, options).run.wait
    unless status.success?
      raise CalledProcessError.new.tap {|e| e.exit_status = status }
    end
    status
  end
end
