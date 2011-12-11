#!/usr/local/bin/ruby

require "subprocess"
require "test/unit"

class TestSubprocess < Test::Unit::TestCase
  def cmd_noop
    ["ruby", "-e42"]
  end
  def cmd_exit(status=0)
    ["ruby", "-e", "exit %d" % status]
  end
  def cmd_sleep(sec=3)
    ["ruby", "-e", "sleep %d" % sec]
  end
  def cmd_sort
    ["ruby", "-e", "puts ARGF.readlines.sort"]
  end
  def cmd_grep(pattern)
    ["ruby", "-e", "puts ARGF.grep(/#{pattern}/)"]
  end
  def cmd_puts(msg="hoge")
    ["ruby", "-e", '$stdout.puts "%s"' % msg]
  end
  def cmd_warn(msg="hoge")
    ["ruby", "-e", '$stderr.puts "%s"' % msg]
  end
  def cmd_warn_puts(errmsg, outmsg)
    ["ruby", "-e", "$stderr.puts '#{errmsg}'; $stdout.puts '#{outmsg}'"]
  end

  def test_normal
    s = Subprocess.new(cmd_noop).run
    pid = s.pid
    assert_kind_of(Integer, pid)
    status = s.wait
    assert_instance_of(Process::Status, status)
    assert_equal(status, s.status)
    assert_equal(pid, status.pid)
    assert_equal(0, status.exitstatus)
    assert_equal(false, status.signaled?)
  end

  def test_shell
    s = Subprocess.new("ruby -e 'exit 1'").run
    pid = s.pid
    assert_kind_of(Integer, pid)
    status = s.wait
    assert_instance_of(Process::Status, status)
    assert_equal(status, s.status)
    assert_equal(pid, status.pid)
    assert_equal(1, status.exitstatus)
    assert_equal(false, status.signaled?)
  end

  def test_terminate
    s = Subprocess.new(cmd_sleep).run
    assert_nil(s.poll)
    assert_nil(s.status)
    sleep 0.1 # XXX
    s.terminate
    status = s.wait
    assert_equal(nil, status.exitstatus)
    assert_equal(Signal.list["TERM"], status.termsig)
  end

  def test_kill
    Subprocess.start(cmd_sleep) {|s|
      assert_instance_of(Subprocess, s)
      assert_nil(s.poll)
      assert_nil(s.status)
      sleep 0.1 # XXX
      s.kill
      status = s.wait
      assert_equal(nil, status.exitstatus)
      assert_equal(Signal.list["KILL"], status.termsig)
    }
  end

  def test_communicate_in_out
    options = {
      :stdin=>:PIPE, :stdout=>:PIPE, # :stderr=>:PIPE,
    }
    input = "foo\nbar\nbaz\n"
    out_data, err_data =
      Subprocess.new(cmd_sort, options).communicate(input)
    assert_equal("bar\nbaz\nfoo\n", out_data)
    assert_equal(nil, err_data)
  end

  def test_communicate_err
    options = {
      :stdout=>:PIPE, :stderr=>:PIPE, # :stdin=>:PIPE,
    }
    out_data, err_data = Subprocess.new(cmd_warn("hoge"), options).communicate
    assert_equal("", out_data)
    assert_equal("hoge\n", err_data)
  end

  def test_communicate_err2out
    options = {
      :stdout=>:PIPE, :stderr=>:STDOUT, :stdin=>:PIPE,
    }
    out_data, err_data = Subprocess.new(cmd_warn("hoge"), options).communicate
    assert_equal("hoge\n", out_data)
    assert_equal(nil, err_data)
  end

  def test_communicate_err2out_merge
    argv = cmd_warn_puts("hoge", "fuga")
    options = {
      :stdin=>:PIPE, :stdout=>:PIPE, :stderr=>:STDOUT,
    }
    out_data, err_data = Subprocess.new(argv, options).communicate
    assert_equal("hoge\nfuga\n", out_data)
    assert_equal(nil, err_data)
  end

  def test_stdio
    argv = ["ruby", "-e", "STDERR.puts 'hoge'; puts ARGF.readlines.sort"]
    options = {
      :stdin=>:PIPE, :stdout=>:PIPE, :stderr=>:PIPE,
    }
    input = "foo\nbar\nbaz\n"
    s = Subprocess.new(argv, options).run
    assert_kind_of(IO, s.stdin)
    assert_kind_of(IO, s.stdout)
    assert_kind_of(IO, s.stderr)
    s.stdin.write(input)
    s.stdin.close
    err_data = s.stderr.read
    assert_equal("hoge\n", err_data)
    out_data = s.stdout.read
    assert_equal("bar\nbaz\nfoo\n", out_data)
    status = s.wait
    assert_equal(0, status.exitstatus)
    assert_equal(false, status.signaled?)
  end

  def test_call
    status = Subprocess.call(cmd_exit(0))
    assert_equal(0, status.exitstatus)
    status = Subprocess.call(cmd_exit(1))
    assert_equal(1, status.exitstatus)
  end

  def test_check_call
    status = Subprocess.check_call(cmd_exit(0))
    assert_equal(0, status.exitstatus)
    begin
      status = Subprocess.check_call(cmd_exit(1))
      fail("expected raise of Subprocess::CalledProcessError")
    rescue => e
      assert_instance_of(Subprocess::CalledProcessError, e)
      assert_equal(1, e.exit_status.exitstatus)
    end
  end

  def test_communicate_in_file
    filename = __FILE__
    pattern = "READ_THIS_LINE_ITSELF"
    out_data, err_data = File.open(filename) {|f|
      Subprocess.new(cmd_grep(pattern), :stdin=>f, :stdout=>:PIPE).communicate
    }
    assert_match(/#{pattern}/, out_data)
  end

  def test_communicate_out_file
    filename = "#{__FILE__}.tmp"
    pattern = "READ_THIS_LINE_ITSELF"
    begin
      out_data, err_data = File.open(filename, "w") {|f|
        options = { :stdin=>:PIPE, :stdout=>f }
        Subprocess.new(cmd_grep(pattern), options).communicate(pattern)
      }
      assert_match(/#{pattern}/m, File.read(filename))
    ensure
      File.unlink(filename) rescue nil
    end
  end

  def test_communicate_out_err_file
    filename_out, filename_err = "#{__FILE__}.out", "#{__FILE__}.err"
    pattern = "READ_THIS_LINE_ITSELF"
    argv = cmd_warn_puts(pattern, pattern)
    begin
      file_out = File.open(filename_out, "w")
      file_err = File.open(filename_err, "w")
      options = { :stdout=>file_out, :stderr=>file_err }
      out_data, err_data = Subprocess.new(argv, options).communicate
      assert_match(/#{pattern}/m, File.read(filename_out))
      assert_match(/#{pattern}/m, File.read(filename_err))
    ensure
      file_out.close rescue nil
      file_err.close rescue nil
      File.unlink(filename_out) rescue nil
      File.unlink(filename_err) rescue nil
    end
  end
end
