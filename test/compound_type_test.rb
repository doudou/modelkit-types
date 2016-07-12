require 'test_helper'

module ModelKit::Types
    describe CompoundType do
        attr_reader :registry, :int32_t, :double_t, :compound_t
        before do
            @registry = Registry.new
            @int32_t   = registry.create_numeric '/int32', size: 4, integer: true, unsigned: false
            @double_t  = registry.create_numeric '/double', size: 8, integer: false
            @compound_t = registry.create_compound '/Test' do |c|
                c.add 'a', int32_t
                c.add 'b', double_t, skip: 5
                c.add 'c', int32_t
            end
        end

        def make_int32(v)
            int32_t.from_buffer([v].pack("l<"))
        end

        def make_double(v)
            double_t.from_buffer([v].pack("E"))
        end

        it "initializes its internal buffer using #initial_buffer_size" do
            registry = Registry.new
            int32 = registry.create_numeric '/int32', size: 4, integer: true, unsigned: false
            vec_m = registry.create_container_model '/vec'
            vec_int32 = registry.create_container vec_m, int32, size: 1
            compound_t = registry.create_compound '/test' do |c|
                c.add 'a', vec_int32
            end
            value = compound_t.new
            assert value.get('a').empty?
        end

        it "computes #initial_buffer_size only once" do
            registry = Registry.new
            int32 = registry.create_numeric '/int32', size: 4, integer: true, unsigned: false
            vec_m = registry.create_container_model '/vec'
            vec_int32 = registry.create_container vec_m, int32, size: 1
            compound_t = registry.create_compound '/test' do |c|
                c.add 'a', vec_int32
            end
            flexmock(vec_int32).should_receive(:initial_buffer_size).once.pass_thru
            result = compound_t.initial_buffer_size
            assert_equal result, compound_t.initial_buffer_size
        end

        describe "#buffer_size_at" do
            it "shortcuts to its own size if fixed size" do
                buffer = compound_t.from_ruby(a: 10, b: 20, c: 30).__buffer
                flexmock(int32_t).should_receive(:buffer_size_at).never
                assert_equal compound_t.size, buffer.size
            end
            it "computes the overall size if variable sized" do
                vec_m = registry.create_container_model '/vec'
                vec_int32  = registry.create_container vec_m, int32_t
                compound_t = registry.create_compound '/VarTest' do |c|
                    c.add 'a', int32_t
                    c.add 'b', vec_int32, skip: 5
                    c.add 'c', int32_t
                end

                buffer = Buffer.new(compound_t.from_ruby(a: 10, b: [11, 12], c: 13).to_byte_array)
                assert_equal 29, compound_t.buffer_size_at(buffer, 0)
            end
        end

        describe "#apply_changes" do
            it "applies changes from variable types" do
                vec_m = registry.create_container_model '/vec'
                vec_int32  = registry.create_container vec_m, int32_t
                compound_t = registry.create_compound '/VarTest' do |c|
                    c.add 'a', int32_t
                    c.add 'b', vec_int32, skip: 5
                    c.add 'c', int32_t
                end

                value = compound_t.from_ruby(a: 10, b: [11, 12], c: 13)
                assert_equal [10, 0, 13], value.__buffer.unpack("l<Q<xxxxxl<")
                value.apply_changes
                assert_equal [10, 2, 11, 12, 13], value.__buffer.unpack("l<Q<l<l<xxxxxl<")
            end
        end

        describe "#__type_offset_and_size" do
            attr_reader :compound
            before do
                @compound = compound_t.from_buffer([10, 0.1, 10].pack("l<Exxxxxl<"))
            end
            it "returns a field's type offset and size" do
                assert_equal [int32_t, 0, 4], compound.__type_offset_and_size('a')
                assert_equal [double_t, 4, 8], compound.__type_offset_and_size('b')
            end
            it "takes into account the skips" do
                assert_equal [int32_t, 17, 4], compound.__type_offset_and_size('c')
            end
            it "caches the result" do
                compound.__type_offset_and_size('c')
                flexmock(compound.__field_offsets).should_receive(:[]).never
                assert_equal [int32_t, 17, 4], compound.__type_offset_and_size('c')
            end
            it "resets the cache in reset_buffer" do
                compound.__type_offset_and_size('c')
                compound.reset_buffer(compound.__buffer)
                flexmock(compound.__field_offsets).should_receive(:[]).at_least.once.pass_thru
                assert_equal [int32_t, 17, 4], compound.__type_offset_and_size('c')
            end
            it "uses the type reported size" do
                int32_t.size = 1
                flexmock(int32_t).should_receive(:buffer_size_at).
                    with(compound.__buffer, 0).once.
                    and_return(4)
                assert_equal [int32_t, 0, 4], compound.__type_offset_and_size('a')
                assert_equal [double_t, 4, 8], compound.__type_offset_and_size('b')
            end
        end

        describe "#get" do
            attr_reader :compound
            before do
                @compound = compound_t.from_buffer([10, 0.1, 20].pack("l<E@17l<"))
            end
            it "raises ArgumentError for a non-existing field" do
                assert_raises(ArgumentError) do
                    compound.get('does_not_exist')
                end
            end
            it "gives access to the first element" do
                assert_equal 10, compound.get('a').to_ruby
            end
            it "gives access to an arbitrary element" do
                assert_equal 0.1, compound.get('b').to_ruby
                assert_equal 20, compound.get('c').to_ruby
            end

            it "accesses the backing buffer for fixed-size elements" do
                flexmock(int32_t).should_receive(:fixed_buffer_size?).and_return(true)
                assert compound.__buffer.contains?(compound.get('a').__buffer)
            end

            it "gives its own buffer to variable-size elements" do
                flexmock(double_t).should_receive(:fixed_buffer_size?).and_return(false)
                flexmock(double_t).should_receive(:buffer_size_at).and_return(8)
                refute compound.__buffer.contains?(compound.get('b').__buffer)
            end
        end

        describe "#set" do
            it "commits to backing buffer for fixed-size fields" do
                compound = compound_t.from_buffer([10, 0.1, 20].pack("l<E@17l<"))
                compound.set('c', make_int32(100))
                assert_equal [10, 0.1, 100].pack("l<E@17l<"),
                    compound.__buffer.to_str
            end
            it "applies on the field's own buffer for variable-size fields" do
                compound = compound_t.from_buffer([10, 0.1, 20].pack("l<E@17l<"))
                flexmock(double_t).should_receive(:fixed_buffer_size?).and_return(false)
                flexmock(double_t).should_receive(:buffer_size_at).and_return(8)
                compound.set('b', make_double(0.2))
                assert_equal [10, 0.1, 20], compound.__buffer.unpack("l<E@17l<")
                assert_equal [0.2], compound.get('b').__buffer.unpack("E")
            end
        end

        describe "#[]=" do
            it "is an alias to set" do
                compound = compound_t.from_buffer([10, 0.1, 20].pack("l<E@17l<"))
                flexmock(compound).should_receive(:set).once.
                    with(key = flexmock, value = flexmock).
                    and_return(flexmock)
                assert_equal value, compound[key] = value
           end
        end

        describe "#[]" do
            it "is an alias to get" do
                compound = compound_t.from_buffer([10, 0.1, 20].pack("l<E@17l<"))
                flexmock(compound).should_receive(:get).once.
                    with(key = flexmock).
                    and_return(value = flexmock)
                assert_equal value, compound[key]
            end
        end

        describe "#each" do
            it "enumerates its fields" do
                compound = compound_t.from_ruby('a' => 10, 'b' => 0.1, 'c' => 20)
                assert_equal [['a', 10], ['b', 0.1], ['c', 20]], compound.each_field.map { |k, v| [k, v.to_ruby] }
            end
        end

        describe "#has_field?" do
            attr_reader :compound
            before do
                @compound = compound_t.from_ruby('a' => 10, 'b' => 0.1, 'c' => 20)
            end
            it "returns true for an existing field" do
                assert compound.has_field?('a')
            end
            it "returns false for an existing field" do
                refute compound.has_field?('does_not_exist')
            end
        end

        describe "#to_simple_value" do
            attr_reader :compound
            before do
                @compound = compound_t.from_ruby('a' => 10, 'b' => 0.1, 'c' => 20)
            end
            it "returns a hash with the values converted" do
                assert_equal Hash['a' => 10, 'b' => 0.1, 'c' => 20],
                    compound.to_simple_value
            end
            it "passes arguments to its fields" do
                flexmock(compound.get('a')).should_receive(:to_simple_value).
                    with(special_float_values: :nil, pack_simple_arrays: true).
                    pass_thru.
                    once
                assert_equal Hash['a' => 10, 'b' => 0.1, 'c' => 20],
                    compound.to_simple_value(special_float_values: :nil, pack_simple_arrays: true)
            end
        end

        describe "#pretty_print" do
            it "pretty-prints itself and its fields" do
                compound = compound_t.from_ruby('a' => 10, 'b' => 0.1, 'c' => 20)
                result = PP.pp(compound, "", 5)
                assert_equal <<-EOTEXT, result
{
  a = 10,
  b = 0.1,
  c = 20
}
                EOTEXT
            end
        end

        describe "#from_ruby" do
            it "initializes the fields from the hash values" do
                compound = compound_t.from_ruby('a' => 1, 'b' => 0.1, 'c' => 2)
                assert_equal 1, compound.get('a').to_ruby
                assert_equal 0.1, compound.get('b').to_ruby
                assert_equal 2, compound.get('c').to_ruby
            end
            it "accepts symbols as keys" do
                compound = compound_t.from_ruby(a: 1, b: 0.1, c: 2)
                assert_equal 1, compound.get('a').to_ruby
                assert_equal 0.1, compound.get('b').to_ruby
                assert_equal 2, compound.get('c').to_ruby
            end
            it "initializes the unspecified fields to empty" do
                compound = compound_t.from_ruby(a: 1, b: 0.1)
                assert_equal 1, compound.get('a').to_ruby
                assert_equal 0.1, compound.get('b').to_ruby
                assert_equal 0, compound.get('c').to_ruby
            end
        end

        describe "#to_ruby" do
            it "converts to a hash with string keys" do
                compound = compound_t.from_ruby(a: 1, b: 0.1, c: 2)
                assert_equal Hash['a' => 1, 'b' => 0.1, 'c' => 2],
                    compound.to_ruby
            end
        end
    end
end
