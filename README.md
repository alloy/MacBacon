MacBacon -- small RSpec clone.
------------------------------

    "Truth will sooner come out from error than from confusion."
                                               ---Francis Bacon

Bacon is a small RSpec clone weighing less than 350 LoC but
nevertheless providing all essential features.

This MacBacon fork is created and maintained by Eloy Durán (@alloy).
It differs with regular Bacon in that it operates properly in a
NSRunloop based environment. I.e. MacRuby/Objective-C. See the
Objective-C runloop macros section for more info.

Whirl-wind tour
===============

    require 'mac_bacon'
    
    describe 'A new array' do
      before do
        @ary = Array.new
      end
      
      it 'should be empty' do
        @ary.should.be.empty
        @ary.should.not.include 1
      end
    
      it 'should have zero size' do
        @ary.size.should.equal 0
        @ary.size.should.be.close 0.1, 0.5
      end
    
      it 'should raise on trying fetch any index' do
        lambda { @ary.fetch 0 }.
          should.raise(IndexError).
          message.should.match(/out of array/)
    
        # Alternatively:
        should.raise(IndexError) { @ary.fetch 0 }
      end
    
      it 'should have an object identity' do
        @ary.should.not.be.same_as Array.new
      end
    
      it 'should perform a long running operation' do
        @ary.performSelector("addObject:", withObject:"soup", afterDelay:0.5)
        wait 0.6 do
          @ary.size.should.be 1
        end
      end
    
      # Custom assertions are trivial to do, they are lambdas returning a
      # boolean vale:
      palindrome = lambda { |obj| obj == obj.reverse }
      it 'should be a palindrome' do
        @ary.should.be.a palindrome
      end
    
      it 'should have super powers' do
        should.flunk "no super powers found"
      end
    end

Now run it:

    $ macbacon whirlwind.rb
    A new array
      - should be empty
      - should have zero size
      - should raise on trying fetch any index
      - should have an object identity
      - should perform a long running operation
      - should be a palindrome
      - should have super powers [MISSING]

    Bacon::Error: no super powers found
    	./whirlwind.rb:44:in `block': A new array - should have super powers

    Bacon::Error: empty specification: A new array should have super powers

    7 specifications (10 requirements), 1 failures, 0 errors

If you want shorter output, use the Test::Unit format:

    $ macbacon -q whirlwind.rb
    ......F
    Bacon::Error: no super powers found
    	./whirlwind.rb:39: A new array - should have super powers
    	./whirlwind.rb:38
    	./whirlwind.rb:3
    
    7 tests, 10 assertions, 1 failures, 0 errors

It also supports TAP:

    $ macbacon -p whirlwind.rb
    ok 1        - should be empty
    ok 2        - should have zero size
    ok 3        - should raise on trying fetch any index
    ok 4        - should have an object identity
    ok 5        - should be a palindrome
    ok 6        - should perform a long running operation
    not ok 7    - should have super powers: FAILED
    # Bacon::Error: no super powers found
    # 	./whirlwind.rb:44: A new array - should have super powers
    1..7
    # 7 tests, 10 assertions, 1 failures, 0 errors

    $ macbacon -p whirlwind.rb | taptap -q
    Tests took 0.00 seconds.
    FAILED tests 7
       7) should have super powers: FAILED

    Failed 1/7 tests, 83.33% okay.

(taptap is available from http://chneukirchen.org/repos/taptap/)

As of Bacon 1.1, it also supports Knock:

    $ macbacon -k whirlwind.rb
    ok - should be empty
    ok - should have zero size
    ok - should raise on trying fetch any index
    ok - should have an object identity
    ok - should be a palindrome
    ok - should perform a long running operation
    not ok - should have super powers: FAILED
    # Bacon::Error: no super powers found
    # 	./whirlwind.rb:4: A new array - should have super powers

    $ bacon -k whirlwind.rb | kn-sum
    7 tests, 1 failed (83.3333% succeeded)

(knock is available from http://github.com/chneukirchen/knock/)


Implemented assertions
======================

* should.<predicate> and should.be.<predicate>
* should.equal
* should.match
* should.be.identical_to / should.be.same_as
* should.raise(*exceptions) { }
* should.change { }
* should.throw(symbol) { }
* should.satisfy { |object| }


Added core predicates
=====================

* Object#true?
* Object#false?
* Proc#change?
* Proc#raise?
* Proc#throw?
* Numeric#close?


before/after
============

before and after need to be defined before the first specification in
a context and are run before and after each specification.

As of Bacon 1.1, before and after do nest in nested contexts.


Shared contexts
===============

You can define shared contexts in Bacon like this:

    shared "an empty container" do
      it "should have size zero" do
      end

      it "should be empty" do
      end
    end

    describe "A new array" do
      behaves_like "an empty container"
    end

These contexts are not executed on their own, but can be included with
behaves_like in other contexts.  You can use shared contexts to
structure suites with many recurring specifications.


Matchers
========

Custom matchers are simply lambdas returning a boolean value, for
example:

    def shorter_than(max_size)
      lambda { |obj| obj.size < max_size }
    end
    
    [1,2,3].should.be shorter_than(5)

You can use modules and extend to group matchers for use in multiple
contexts.


Concurrency
===========

When the `-c`, or `--concurrency`, option is passed to the `macbacon`
command-line tool, than all specifications will be run concurrent through the
use of [Grand Central Dispatch][GCD].

Each specification runs in its own thread and gets its own runloop. In case you
wat to perform certain specifications on the main thread (e.g. when dealing
with views), you can specify that like so:

    describe "Deals with the UI" do
      self.run_on_main_thread = true

      it "runs on the main thread" do
        # ...
      end
    end


Objective-C runloop macros
==========================


Often in Objective-C apps, code will *not* execute immediately, but
scheduled on a runloop for later execution. Therefor a mechanism is
provided that will postpone execution of blocks for a period of time.

(Note that using a block is imply syntactic sugar, you can call wait
without a block too.)

All these macros may be used in before and after filters as well.


### `wait` with fixed period of time

    it 'should perform a long running operation' do
      # Here a method call is scheduled to be performed ~0.5 seconds in the future
      @ary.performSelector("addObject:", withObject:"soup", afterDelay:0.5)
      wait 0.6 do
        # This block is executed ~0.6 seconds in the future
        @ary.size.should.be 1
      end
    end


### `wait` without fixed period of time, until `resume` is called

By default this usage of `wait` will wait for 10 seconds. If `resume`
has not been called by that time, the spec fails.

    def aDelegateCallbackMethod(sender)
      @delegateCallbackMethodCalled = true
      resume
    end

    it 'should wait until notified' do
      # Here a method is called that in the near future will result in the object calling back the delegate
      @object.delegate = self
      @object.startLongRunningMethod
      wait do
        # This block is executed once aDelegateCallbackMethod is called
        @delegateCallbackMethodCalled.should == true
      end
    end

If you want to specify the timeout, you can do that like so:

    describe "specs that will wait for resume" do
      self.timeout = 20 # seconds
    end


### `wait_for_change` (Key-Value Observing)

This macro makes the specification an observer of the key path of the
given object for the duration of the specification.

Like with `wait` without a fixed period, this usage of
`wait_for_change` will by default wait for 10 seconds. If the KVO
message has not arrived by that time, the spec fails.

    class AKeyValueObservableClass
      attr_accessor :an_attribute

      def compute_an_attribute
        # trust me, this takes a few ms
        self.an_attribute = 'changed'
      end
    end

    it 'should wait until AKeyValueObservableClass#an_attribute changes' do
      # Here a method is called that in the near future will update the 'an_attribute' value of the object
      observable.compute_an_attribute
      wait_for_change observable, 'an_attribute' do
        # This block is executed once 'an_attribute' has changed value
        observable.an_attribute.should == 'changed'
      end
    end


Load NIBs
=========

In case you have a NIB that defines the UI for the controller you're testing,
then you can use the `load_nib` method to easily do so:

    describe "PreferencesController" do
      before do
        @controller = PreferencesController.new
        nib_path = File.join(SRC_ROOT, 'app/views/PreferencesWindow.xib')
        @top_level_objects = load_nib(nib_path, @controller)
      end
      
      # tests...
      
    end


bacon standalone runner
=======================

    -s, --specdox            do AgileDox-like output (default)
    -q, --quiet              do Test::Unit-like non-verbose output
    -p, --tap                do TAP (Test Anything Protocol) output
    -k, --knock              do Knock output
    -o, --output FORMAT      do FORMAT (SpecDox/TestUnit/Tap) output
    -Q, --no-backtrace       don't print backtraces  
    -a, --automatic          gather tests from ./test/, include ./lib/
    -c, --concurrent         runs multiple specs concurrently on multiple GCD threads
    -n, --name NAME          runs tests matching regexp NAME
    -t, --testcase TESTCASE  runs tests in TestCases matching regexp TESTCASE


Object#should
=============

You can use Object#should outside of contexts, where the result of
assertion will be returned as a boolean.  This is nice for
demonstrations, quick checks and doctest tests.

    >> require 'mac_bacon'
    >> (1 + 1).should.equal 2
    => true
    >> (6*9).should.equal 42
    => false


Converting specs
================

spec-converter is a simple tool to convert test-unit or dust style
tests to test/spec specs.

It can be found at http://opensource.thinkrelevance.com/wiki/spec_converter.


Thanks to
=========

* Michael Fellinger, for fixing Bacon for 1.9 and various improvements.
* Gabriele Renzi, for implementing Context#should.
* James Tucker, for the autotest support.
* Yossef Mendelssohn, for nested contexts.
* everyone contributing bug fixes.


History
=======

* January 7, 2008: First public release 0.9.

* July 6th, 2008: Second public release 1.0.
  * Add Context#should as a shortcut for Context#it('should ' + _).
  * describe now supports multiple arguments for better organization.
  * Empty specifications are now erroneous.
  * after-blocks run in the case of exceptions too.
  * Autotest support.
  * Bug fixes.

* November 30th, 2008: Third public release 1.1.
  * Nested before/after.
  * Add -Q/--no-backtraces to not show details about failed specifications.
  * Add Knock output.
  * Bug fixes.

* January 10th, 2011: MacBacon fork release 1.1
  * Make it work in a NSRunloop environment
  * Add `wait`
  * Remove extras, for now

* March 12th, 2011: MacBacon fork release 1.3
  * Add NIB helper
  * exit with non-zero status when there were failures/errors
  * Add `wait` without explicit time
  * Add `wait_for_change`

* TODO, 2012: MacBacon fork release 1.4
  * Use GCD to run specs concurrently when started with the `-c` or
    `--concurrency` command-line options.
  * Add delegate support, which notifies a delegate when a spec will
    start and once it finishes and also once Bacon has finished the
    run.
  * Simplified internals by removing callback/delegate system in
    favor of nested runloops.


Contact
=======

Please mail bugs, suggestions and patches for Bacon to
<mailto:chneukirchen@gmail.com>

Git repository (patches rebased on HEAD are most welcome):
https://github.com/chneukirchen/bacon
git://github.com/chneukirchen/bacon.git

For MacBacon contact
<mailto:eloy.de.enige@gmail.com>

And repository location:
https://github.com/alloy/MacBacon
git://github.com/alloy/MacBacon.git


Copying
=======

Copyright (C) 2007 - 2012 Christian Neukirchen <http://purl.org/net/chneukirchen>

Copyright (C) 2011 - 2012 Eloy Durán <eloy.de.enige@gmail.com>

Bacon is freely distributable under the terms of an MIT-style license.
See COPYING or http://www.opensource.org/licenses/mit-license.php.


Links
=====

* Behavior-Driven Development:: <http://behaviour-driven.org/>
* RSpec:: <http://rspec.rubyforge.org/>
* test/spec:: <http://test-spec.rubyforge.org/>

* Christian Neukirchen:: <http://chneukirchen.org/>
* Eloy Durán:: <http://twitter.com/alloy>


[GCD]: https://developer.apple.com/library/mac/documentation/General/Conceptual/ConcurrencyProgrammingGuide/OperationQueues/OperationQueues.html#//apple_ref/doc/uid/TP40008091-CH102-SW1
