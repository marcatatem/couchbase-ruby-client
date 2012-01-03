# Author:: Couchbase <info@couchbase.com>
# Copyright:: 2011, 2012 Couchbase, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require File.join(File.dirname(__FILE__), 'setup')

class TestStore < MiniTest::Unit::TestCase

  def setup
    @mock = start_mock
  end

  def teardown
    stop_mock(@mock)
  end

  def test_trivial_set
    connection = Couchbase.new(:port => @mock.port)
    cas = connection.set(test_id, "bar")
    assert(cas > 0)
  end

  def test_set_with_cas
    connection = Couchbase.new(:port => @mock.port)

    cas1 = connection.set(test_id, "bar1")
    assert cas1 > 0

    assert_raises(Couchbase::Error::KeyExists) do
      connection.set(test_id, "bar2", :cas => cas1+1)
    end

    cas2 = connection.set(test_id, "bar2", :cas => cas1)
    assert cas2 > 0
    refute_equal cas2, cas1

    cas3 = connection.set(test_id, "bar3")
    assert cas3 > 0
    refute_equal cas3, cas2
    refute_equal cas3, cas1
  end

  def test_add
    connection = Couchbase.new(:port => @mock.port)

    cas1 = connection.add(test_id, "bar")
    assert cas1 > 0

    assert_raises(Couchbase::Error::KeyExists) do
      connection.add(test_id, "bar")
    end

    assert_raises(Couchbase::Error::KeyExists) do
      connection.add(test_id, "bar", :cas => cas1)
    end
  end

  def test_replace
    connection = Couchbase.new(:port => @mock.port)

    assert_raises(Couchbase::Error::NotFound) do
      connection.replace(test_id, "bar")
    end

    cas1 = connection.set(test_id, "bar")
    assert cas1 > 0

    connection.replace(test_id, "bar")
  end

  def test_acceptable_keys
    connection = Couchbase.new(:port => @mock.port)

    cas = connection.set(test_id.to_sym, "bar")
    assert cas > 0

    cas = connection.set(test_id.to_s, "bar")
    assert cas > 0

    assert_raises(TypeError) do
      connection.set(nil, "bar")
    end

    obj = {:foo => "bar", :baz => 1}
    assert_raises(TypeError) do
      connection.set(obj, "bar")
    end

    class << obj
      alias :to_str :to_s
    end

    connection.set(obj, "bar")
    assert cas > 0
  end

  def test_asynchronous_set
    connection = Couchbase.new(:port => @mock.port)
    ret = nil
    connection.run do |conn|
      conn.set(test_id("1"), "foo1") {|res| ret = res}
      conn.set(test_id("2"), "foo2") # ignore result
      assert_equal 2, conn.seqno
    end
    assert ret.is_a?(Couchbase::Result)
    assert ret.success?
    assert_equal test_id("1"), ret.key
    assert_equal :set, ret.operation
    assert ret.cas.is_a?(Numeric)
  end

  def test_it_raises_error_when_appending_or_prepending_to_missing_key
    connection = Couchbase.new(:port => @mock.port)

    assert_raises(Couchbase::Error::NotStored) do
      connection.append(test_id(:missing), "foo")
    end

    assert_raises(Couchbase::Error::NotStored) do
      connection.prepend(test_id(:missing), "foo")
    end
  end

  def test_append
    connection = Couchbase.new(:port => @mock.port, :default_format => :plain)

    cas1 = connection.set(test_id, "foo")
    assert cas1 > 0
    cas2 = connection.append(test_id, "bar")
    assert cas2 > 0
    refute_equal cas2, cas1

    val = connection.get(test_id)
    assert_equal "foobar", val
  end

  def test_prepend
    connection = Couchbase.new(:port => @mock.port, :default_format => :plain)

    cas1 = connection.set(test_id, "foo")
    assert cas1 > 0
    cas2 = connection.prepend(test_id, "bar")
    assert cas2 > 0
    refute_equal cas2, cas1

    val = connection.get(test_id)
    assert_equal "barfoo", val
  end

  ArbitraryData = Struct.new(:baz)

  def test_set_using_brackets
    connection = Couchbase.new(:port => @mock.port)

    connection[test_id(1)] = "foo"
    val = connection.get(test_id(1))
    assert_equal "foo", val

    if RUBY_VERSION =~ /^1\.9/
      eval <<-EOC
      connection[test_id(2), :flags => 0x1100] = "bar"
      val, flags = connection.get(test_id(2), :extended => true)
      assert_equal "bar", val
      assert_equal 0x1100, flags

      connection[test_id(3), :format => :marshal] = ArbitraryData.new("thing")
      val = connection.get(test_id(3))
      assert val.is_a?(ArbitraryData)
      assert_equal "thing", val.baz
      EOC
    end
  end
end
