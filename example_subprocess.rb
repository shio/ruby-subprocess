#!/usr/local/bin/ruby

require "subprocess"

if true
  puts "------------------------------------------------------------"
  puts "output = `date +'%Y-%m-%d %H:%M:%D'`"
  puts "--------"

  output = Subprocess.new(["date", "+%Y-%m-%d %H:%M:%S"],
                               :stdout=>:PIPE).communicate[0]
  puts "output => #{output.inspect}"
end

if true
  puts "------------------------------------------------------------"
  puts "output = `ls -laFg | grep rb`"
  puts "--------"

  p1 = Subprocess.new(["ls", "-laFg"], :stdout=>:PIPE).run
  p2 = Subprocess.new(["grep", "rb"], :stdin=>p1.stdout, :stdout=>:PIPE)
  output = p2.communicate[0]
  p1.wait
  output.each_line {|l|
    puts "output => #{l}"
  }
end

if true
  puts "------------------------------------------------------------"
  puts "sts = os.system('date')"
  puts "--------"

  # XXX :shell is not implemented
  s = Subprocess.new(["date"], :shell=>true).run
  sts = s.wait.success?
  puts "sts => #{sts}"
  puts "--------"
end
