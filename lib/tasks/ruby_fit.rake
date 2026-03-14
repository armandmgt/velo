namespace :ruby_fit do
  desc "Compile the C extension for ruby_fit local gem"
  task :compile do
    puts "== Compiling ruby_fit extension =="
    Dir.chdir("lib/ruby_fit") do
      sh "rake compile"
    end
  end

  desc "Clean the compiled ruby_fit extension"
  task :clean do
    puts "== Cleaning ruby_fit extension =="
    Dir.chdir("lib/ruby_fit") do
      sh "rake clobber"
    end
  end
end

# Hook it into assets:precompile so it's guaranteed during build
if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance([ "ruby_fit:compile" ])
end

# Hook it into test tasks
if Rake::Task.task_defined?("test:prepare")
  Rake::Task["test:prepare"].enhance([ "ruby_fit:compile" ])
end
