# Bacon -- small RSpec clone.
#
# "Truth will sooner come out from error than from confusion." ---Francis Bacon

# Copyright (C) 2007, 2008 Christian Neukirchen <purl.org/net/chneukirchen>
#
# Bacon is freely distributable under the terms of an MIT-style license.
# See COPYING or http://www.opensource.org/licenses/mit-license.php.

framework "Cocoa"
require "mac_bacon/helpers"

# We need to use Kernel::print when printing which specification is being run.
# But we want to know this as soon as possible, hence we need to sync.
$stdout.sync = true

module Bacon
  VERSION = "1.4"


  class << self
    attr_accessor :restrict_name

    attr_accessor :backtraces

    # This can be used by a `client' to receive status updates:
    # * When a spec will start running: bacon_specification_will_start(spec)
    # * When a spec has finished running: bacon_specification_did_finish(spec)
    # * When Bacon has finished a spec run.
    attr_accessor :delegate

    attr_accessor :concurrent
    alias_method  :concurrent?, :concurrent

    def clear
      @contexts = @specifications = @requirements = nil
    end

    def contexts
      @contexts ||= []
    end

    def specifications
      @specifications ||= []
    end

    def requirements
      @requirements ||= []
    end

    # IMPORTANT!
    #
    # Make sure to never call this method directly from the main GCD queue.
    # Instead do something like:
    #
    #   Bacon.performSelector('run', withObject:nil, afterDelay:0)
    def run
      @timer ||= Time.now
      self.performSelector(concurrent? ? "run_all_specs_concurrent" : "run_all_specs_serial", withObject:nil, afterDelay:0)
      NSApplication.sharedApplication.run
    end

    def run_all_specs_serial
      contexts.each do |context|
        context.specifications.each do |spec|
          begin
            spec.run
          rescue Object => e
            puts "An error bubbled up, this should really not happen! The error was: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
            raise e
          end
        end
      end
      bacon_did_finish
    end

    def run_all_specs_concurrent
      main_queue       = Dispatch::Queue.main
      concurrent_queue = Dispatch::Queue.concurrent
      group            = Dispatch::Group.new
      contexts.each do |context|
        queue = context.run_on_main_thread? ? main_queue : concurrent_queue
        context.specifications.each do |spec|
          queue.async(group) do
            begin
              spec.performSelector('run', withObject:nil, afterDelay:0)
              CFRunLoopRun() unless context.run_on_main_thread? # Should already have a running runloop!
            rescue Object => e
              puts "An error bubbled up on a GCD thread, this should really not happen! The error was: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
            end
          end
        end
      end
      # TODO bug in MacRuby which thinks that the main queue is not a Queue object
      #group.notify(main_queue) do
      group.notify(concurrent_queue) do
        #self.performSelectorOnMainThread('bacon_did_finish', withObject:nil, waitUntilDone:true)
        Dispatch::Queue.main.async do
          bacon_did_finish
        end
        # TODO MacRuby bug, leads to segfault
        #Bacon.dispatch_on_main_thread { bacon_did_finish }
      end
    end

    def dispatch_on_main_thread(&block)
      # TODO MacRuby bug/feature, can't compare two Queue objects directly, have to use their names
      if Dispatch::Queue.current.to_s == Dispatch::Queue.main.to_s
        block.call
      else
        Dispatch::Queue.main.sync(&block)
      end
    end

    private

    def bacon_did_finish
      if delegate.respond_to?('bacon_did_finish')
        delegate.bacon_did_finish
      end
      handle_summary
      exit Counter.not_passed
    end

  end


  Shared = Hash.new { |_, name|
    raise NameError, "no such context: #{name.inspect}"
  }

  self.restrict_name = //
  self.backtraces    = true
  self.concurrent    = false


  module Counter
    class << self
      def specifications_ran
        Bacon.specifications.select(&:finished?).size
      end

      def requirements_ran
        Bacon.requirements.size
      end

      def not_passed
        Bacon.specifications.select { |s| !s.passed? }.size
      end

      def failures
        Bacon.specifications.select(&:failure?).size
      end

      def errors
        Bacon.specifications.select(&:error?).size
      end
    end
  end


  # TODO for now we'll just use dots, which works best in a concurrent env
  module SpecDoxOutput
    def handle_context_begin(context)
      # Nested contexts do _not_ have an extra line between them and their parent.
      #puts if context.context_depth == 1

      #spaces = "  " * (context.context_depth - 1)
      #puts spaces + context.name
    end

    def handle_context_end(context)
    end

    def handle_specification_begin(specification)
      #spaces = "  " * (specification.context.class.context_depth - 1)
      ##print "#{spaces}  - #{specification.description}"
      #puts "#{spaces}  - #{specification.description}"
    end

    def handle_specification_end(error)
      #puts error.empty? ? "" : " [#{error}]"
      print '.'
    end

    def summary
      "%d specifications (%d requirements), %d failures, %d errors" %
        [Counter.specifications_ran, Counter.requirements_ran, Counter.failures, Counter.errors]
    end

    def handle_summary
      if Bacon.backtraces
        puts
        puts
        Bacon.specifications.each do |spec|
          unless spec.passed?
            puts spec.error_log
            puts
          end
        end
      end
      puts "Took: %.6f seconds." % (Time.now - @timer).to_f
      @timer = nil
      puts
      puts summary
    end
  end
  extend SpecDoxOutput


  class Error < RuntimeError
    attr_accessor :count_as

    def initialize(count_as, message)
      @count_as = count_as
      super message
    end

    def count_as_failure?
      @count_as == :failure
    end

    def count_as_error?
      @count_as == :error
    end
  end


  class Context
    attr_reader :specification

    def initialize(specification)
      @specification = specification
    end

    def raise?(*args, &block); block.raise?(*args); end
    def throw?(*args, &block); block.throw?(*args); end
    def change?(*args, &block); block.change?(*args); end

    def should(*args, &block)
      if self.class.context_depth == 0
        it('should '+args.first,&block)
      else
        super(*args,&block)
      end
    end

    def describe(*args, &block)
      self.class.describe(*args, &block)
    end

    # If no explicit time to wait is given, then execution can be resumed by
    # calling the #resume method or until the Context#timeout has been reached.
    def wait(seconds = nil)
      if seconds
        CFRunLoopRunInMode(KCFRunLoopDefaultMode, seconds, false)
      else
        @postpone_execution = true
        CFRunLoopRunInMode(KCFRunLoopDefaultMode, 0.001, false) while @postpone_execution
      end
      yield if block_given?
    end

    def resume
      @postpone_execution = false
    end

    def wait_for_change(object_to_observe, key_path, &block)
      object_to_observe.addObserver(self, forKeyPath:key_path, options:0, context:nil)
      wait(&block)
    end

    def observeValueForKeyPath(key_path, ofObject:object, change:_, context:__)
      resume
    end

    class << self
      attr_reader :name, :block, :context_depth, :specifications, :defined_in
      attr_accessor :run_on_main_thread, :timeout

      def init_context(name, context_depth, before = nil, after = nil, &block)
        # find the first file in the backtrace which is not this file
        if defined_in = caller.find { |line| line[0,__FILE__.size] != __FILE__ }
          defined_in = File.expand_path(defined_in.match(/^(.+?):\d+/)[1])
        else
          puts "[!] Unable to determine the file in which the context is defined."
        end

        context = Class.new(self) do
          @name = name
          @before, @after = (before ? before.dup : []), (after ? after.dup : [])
          @block = block
          @specifications = []
          @context_depth = context_depth
          @timeout = 10 # seconds
          @defined_in = defined_in
        end
        Bacon.contexts << context
        context.class_eval(&block)
        context
      end

      def run_on_main_thread?
        @run_on_main_thread || !Bacon.concurrent?
      end

      def before(&block); @before << block; end
      def after(&block);  @after << block; end

      def behaves_like(*names)
        names.each { |name| class_eval(&Shared[name]) }
      end

      def it(description, &block)
        return unless "#{@name} #{description}" =~ Bacon.restrict_name
        block ||= lambda { should.flunk "not implemented" }
        spec = Specification.new(self, description, block, @before, @after)
        @specifications << spec
        spec
      end

      def describe(*args, &block)
        args.unshift(name)
        init_context(args.join(' '), @context_depth + 1, @before, @after, &block)
      end

      alias_method :context, :describe
    end
  end # Context


  class Specification
    attr_reader :description, :context
    attr_accessor :delegate

    def initialize(context_class, description, block, before_filters, after_filters)
      @context = context_class.new(self)
      @description, @block = description, block
      @before_filters, @after_filters = before_filters.dup, after_filters.dup

      @finished = false

      Bacon.specifications << self
    end

    def delegate
      # Add the ability to override, but don't cache Bacon.delegate here so it
      # can be changed for all Specification instances from Bacon.delegate.
      @delegate || Bacon.delegate
    end

    def run
      @timer = NSTimer.scheduledTimerWithTimeInterval(@context.class.timeout,
                                               target:self,
                                             selector:'timedout!',
                                             userInfo:nil,
                                              repeats:false)

      #Bacon.dispatch_on_main_thread do
      Dispatch::Queue.main.async do
        Bacon.handle_specification_begin(self)
        if delegate.respond_to?('bacon_specification_will_start:')
          delegate.bacon_specification_will_start(self)
          #delegate.performSelectorOnMainThread('bacon_specification_will_start:', withObject:self, waitUntilDone:true)
        end
      end

      @before_filters.each { |f| @context.instance_eval(&f) }
      @number_of_requirements_before = Bacon.requirements.size
      @context.instance_eval(&@block)

      if passed? && Bacon.requirements.size == @number_of_requirements_before
        # the specification did not contain any requirements, so it flunked
        raise Error.new(:missing, "empty specification: #{full_name}")
      end

    rescue Object => e
      @exception = e
    ensure
      begin
        @after_filters.each { |f| @context.instance_eval(&f) }
      rescue Object => e
        @exception = e
      ensure
        @timer.invalidate
        @finished = true
        #Bacon.dispatch_on_main_thread do
        Dispatch::Queue.main.async do
          Bacon.handle_specification_end(error_message || '')
          if delegate.respond_to?('bacon_specification_did_finish:')
            delegate.bacon_specification_did_finish(self)
            #delegate.performSelectorOnMainThread('bacon_specification_did_finish:', withObject:self, waitUntilDone:true)
          end
        end
        # Never kill the runloop of the main thread!
        unless Dispatch::Queue.current.to_s == Dispatch::Queue.main.to_s
          CFRunLoopStop(CFRunLoopGetCurrent())
        end
      end
    end

    # TODO does not actually continue the spec execution...
    def timedout!
      puts "TIMED OUT: #{full_name}"
      @exception = Error.new(:error, "timed out: #{full_name}")
      @finished = true
      if Dispatch::Queue.current.to_s == Dispatch::Queue.main.to_s
        puts "OH NOES, TRYING TO KILL THE RUNLOOP OF THE MAIN THREAD!"
      end
      #Bacon.dispatch_on_main_thread do
      Dispatch::Queue.main.async do
        Bacon.handle_specification_end(error_message || '')
        if delegate.respond_to?('bacon_specification_did_finish:')
          delegate.bacon_specification_did_finish(self)
          #delegate.performSelectorOnMainThread('bacon_specification_did_finish:', withObject:self, waitUntilDone:true)
        end
      end
      CFRunLoopStop(CFRunLoopGetCurrent())
    end

    def full_name
      "#{@context.class.name} #{@description}"
    end

    def finished?
      @finished
    end

    def passed?
      @exception.nil?
    end

    def bacon_error?
      @exception.kind_of?(Error)
    end

    def failure?
      @exception.count_as_failure? if bacon_error?
    end

    def error?
      !@exception.nil? && !failure?
    end

    def pending?
      error_message == 'MISSING'
    end

    def error_message
      if bacon_error?
        @exception.count_as.to_s.upcase
      elsif @exception
        "ERROR: #{@exception.class}"
      end
    end

    def filtered_backtrace
      $DEBUG ? @exception.backtrace : @exception.backtrace.find_all { |line| line !~ /bin\/macbacon|\/mac_bacon\.rb:\d+/ }
    end

    def error_log
      if @exception
        log = ''
        log << "#{@exception.class}: #{@exception.message}\n"
        filtered_backtrace.each_with_index { |line, i|
          log << "\t#{line}#{i==0 ? ": #{@context.class.name} - #{@description}" : ""}\n"
        }
        log
      end
    end
  end # Specification

end


class Object
  def true?; false; end
  def false?; false; end
end

class TrueClass
  def true?; true; end
end

class FalseClass
  def false?; true; end
end

class Proc
  def raise?(*exceptions)
    call
  rescue *(exceptions.empty? ? RuntimeError : exceptions) => e
    e
  else
    false
  end

  def throw?(sym)
    catch(sym) {
      call
      return false
    }
    return true
  end

  def change?
    pre_result = yield
    called = call
    post_result = yield
    pre_result != post_result
  end
end

class Numeric
  def close?(to, delta)
    (to.to_f - self).abs <= delta.to_f  rescue false
  end
end


class Object
  def should(*args, &block)    Should.new(self).be(*args, &block)                     end
end

module Kernel
  private
  def describe(*args, &block) Bacon::Context.init_context(args.join(' '), 1, &block)  end
  def shared(name, &block)    Bacon::Shared[name] = block                             end
  alias_method :context, :describe
end

class Should
  # Kills ==, ===, =~, eql?, equal?, frozen?, instance_of?, is_a?,
  # kind_of?, nil?, respond_to?, tainted?
  instance_methods.each { |name| undef_method name  if name =~ /\?|^\W+$/ }

  def initialize(object)
    @object = object
    @negated = false
    Bacon.requirements << self
  end

  def not(*args, &block)
    @negated = !@negated

    if args.empty?
      self
    else
      be(*args, &block)
    end
  end

  def be(*args, &block)
    if args.empty?
      self
    else
      block = args.shift  unless block_given?
      satisfy(*args, &block)
    end
  end

  alias a  be
  alias an be

  def satisfy(*args, &block)
    if args.size == 1 && String === args.first
      description = args.shift
    else
      description = ""
    end

    r = yield(@object, *args)
    # TODO not sure if and how we should fix this
    #if Bacon::Counter[:depth] > 0
      raise Bacon::Error.new(:failed, description)  unless @negated ^ r
      r
    #else
      #@negated ? !r : !!r
    #end
  end

  def method_missing(name, *args, &block)
    name = "#{name}?"  if name.to_s =~ /\w[^?]\z/

    desc = @negated ? "not " : ""
    desc << @object.inspect << "." << name.to_s
    desc << "(" << args.map{|x|x.inspect}.join(", ") << ") failed"

    satisfy(desc) { |x| x.__send__(name, *args, &block) }
  end

  def equal(value)         self == value      end
  def match(value)         self =~ value      end
  def identical_to(value)  self.equal? value  end
  alias same_as identical_to

  def flunk(reason="Flunked")
    raise Bacon::Error.new(:failed, reason)
  end
end
