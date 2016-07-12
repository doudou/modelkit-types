require 'test_helper'

module ModelKit::Types
    describe ContainerType do
        attr_reader :registry, :int32_t, :container_m, :container_t, :ten
        before do
            @registry = Registry.new
            @int32_t = registry.create_numeric '/int32', size: 4, integer: true, unsigned: false
            @ten = make_int32(10)
            @container_m = registry.create_container_model '/std/vector'
            @container_t = registry.create_container container_m, int32_t
        end

        def make_int32(value)
            int32_t.from_buffer([value].pack("l<"))
        end

        def make_container(*values)
            raw = [values.size, *values].pack("Q<l<*")
            container_t.from_buffer(raw)
        end

        it "newly creates a zero-sized container" do
            assert container_t.new.empty?
        end

        it "does not care about the container's declared size" do
            container_t = registry.create_container container_m, int32_t, typename: '/weird_size', size: 1
            assert container_t.new.empty?
        end

        it "infers the size from the buffered data" do
            assert_equal 2, container_t.from_buffer([2].pack("Q<")).size
        end

        describe "#buffer_size_at" do
            it "accounts for the index" do
                buffer = container_t.from_ruby([10, 11]).__buffer
                assert_equal 16, container_t.buffer_size_at(buffer, 0)
            end
            it "delegates to its element's type for variable-sized elements" do
                vec_vec_int32 = registry.create_container container_m, container_t
                buffer = "garbage" + vec_vec_int32.from_ruby([[10, 11], [12]]).to_byte_array.to_types_buffer + "garbage"
                assert_equal 36, vec_vec_int32.buffer_size_at(buffer.to_types_buffer, 7)
            end
        end

        describe "#get" do
            attr_reader :raw, :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            it "gets a never accessed value from its backing buffer" do
                assert_equal 20, container.get(1).to_ruby
            end
            it "caches an accessed value" do
                assert_same container.get(1), container.get(1)
            end
            it "raises if the index is out of bounds" do
                assert_raises(RangeError) do
                    container.get(4)
                end
                assert_raises(RangeError) do
                    container.get(5)
                end
                assert_raises(RangeError) do
                    container.get(-1)
                end
            end

            describe "fixed-size elements" do
                it "returns an element that refers to the container's backing buffer" do
                    assert container.__buffer.contains?(container.get(1).__buffer)
                end
            end
            describe "variable-size elements" do
                before do
                    flexmock(container).should_receive(:__element_fixed_buffer_size?).and_return(false)
                end
                it "returns an element that has its own backing buffer" do
                    assert container.get(1).__buffer.whole?
                end
            end
        end

        describe "#set" do
            attr_reader :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            it "resets an existing element from the provided value" do
                container.set(3, ten)
                assert_equal 10, container.get(3).to_ruby
            end
            it "raises if the index is out of bounds" do
                assert_raises(RangeError) do
                    container.get(4)
                end
                assert_raises(RangeError) do
                    container.get(5)
                end
                assert_raises(RangeError) do
                    container.get(-1)
                end
            end
            describe "fixed-size elements" do
                it "commits the value to the original backing buffer if within the container's original size" do
                    container.set(3, ten)
                    assert_equal [4, 10, 20, 30, 10], container.__buffer.to_str.unpack("Q<l<*")
                end
                it "copies it to the existing cached element if outside the backing buffer" do
                    container.push(int32_t.from_buffer([100].pack("l<")))
                    element = container.get(4)
                    assert_equal 100, element.to_ruby
                    container.set(4, ten)
                    assert_equal [10].pack("l<"), element.__buffer.to_str
                end
            end
            describe "variable-sized elements" do
                before do
                    flexmock(container).should_receive(:__element_fixed_buffer_size?).and_return(false)
                end
                it "stores a copy of the provided argument" do
                    container.set(3, ten)
                    assert_equal [4, 10, 20, 30, 40].pack("Q<l<*"), container.__buffer.to_str
                    assert container.get(3).__buffer.whole?
                    refute_same ten.__buffer.backing_buffer, container.get(3).__buffer.backing_buffer
                end
                it "resets a cached element's content" do
                    container.set(3, make_int32(100))
                    element = container.get(3)
                    container.set(3, ten)
                    assert_same element, container.get(3)
                    assert_equal 10, element.to_ruby
                end
            end
        end

        describe "#clear" do
            attr_reader :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            it "removes all elements from the container" do
                container.clear
                assert container.empty?
            end
            it "does not reload from the underlying buffer if pushing and getting" do
                container.clear
                container.push(ten)
                assert_equal 10, container.get(0).to_ruby
            end
        end

        describe "#push" do
            attr_reader :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            it "adds an element to the container" do
                container.push(ten)
                assert_equal 10, container.get(4).to_ruby
                assert_equal 5, container.size
            end
            it "is aliased to #<<" do
                flexmock(container).should_receive(:push).with(value = flexmock).once
                container << value
            end
        end

        describe "#concat" do
            attr_reader :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            it "adds all elements of the provided enumerator" do
                container.concat(container)
                assert_equal [10, 20, 30, 40, 10, 20, 30, 40], container.map(&:to_ruby)
            end
        end
        
        describe "#delete_if" do
            attr_reader :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            it "deletes the elements for which the block returns true" do
                container.delete_if do |v|
                    (v.to_ruby / 10) % 2 == 0
                end
                assert_equal [10, 30], container.map(&:to_simple_value)
            end
            it "only shifts added elements without touching their backing buffers" do
                container.push(make_int32(50))
                container.push(make_int32(60))
                container.delete_if do |v|
                    (v.to_ruby / 10) % 2 == 0
                end
                assert_equal [10, 30, 50], container.map(&:to_simple_value)
            end
            it "only shifts independent elements without touching their backing buffers" do
                flexmock(container).should_receive(:__element_fixed_buffer_size?).and_return(false)
                container.push(make_int32(50))
                container.push(make_int32(60))
                container.delete_if do |v|
                    (v.to_ruby / 10) % 2 == 0
                end
                assert_equal [10, 30, 50], container.map(&:to_simple_value)
            end
        end

        describe "#pretty_print" do
            attr_reader :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            it "pretty prints" do
                container.push(make_int32(50))
                result = PP.pp(container, "", 10)
                assert_equal <<-EOTEXT, result
[
  [0] = 10,
  [1] = 20,
  [2] = 30,
  [3] = 40,
  [4] = 50
]
                EOTEXT
            end
        end

        describe "#apply_changes" do
            attr_reader :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            describe "fixed size elements" do
                # NOTE: for fixed-size elements, elements within the original
                # buffer size are updated in-place, no need to commit them to
                # the backing buffer

                it "appends new elements to the buffer" do
                    container.push(make_int32(50))
                    container.apply_changes
                    assert_equal [5, 10, 20, 30, 40, 50], container.__buffer.to_str.unpack("Q<l<*")
                end
                it "resets the cached element buffers after an append" do
                    el1 = container.get(1)
                    el4 = container.push(make_int32(50))
                    container.apply_changes
                    assert_same el1, container.get(1)
                    assert_same el4, container.get(4)
                    assert container.__elements.all? { |el| !el || container.__buffer.contains?(el.__buffer) }
                    assert_equal [10, 20, 30, 40, 50], container.map(&:to_simple_value)
                end
                it "removes trailing elements" do
                    container.resize(3)
                    container.apply_changes
                    assert_equal [3, 10, 20, 30], container.__buffer.to_str.unpack("Q<l<*")
                end
                it "resets the cached element buffers after a removal" do
                    el1 = container.get(1)
                    assert_same el1, container.get(1)
                    container.resize(3)
                    container.apply_changes
                    assert_same el1, container.get(1)
                    assert container.__elements.all? { |el| !el || container.__buffer.contains?(el.__buffer) }
                    assert_equal [10, 20, 30], container.map(&:to_simple_value)
                end
            end
            describe "variable sized elements" do
                before do
                    flexmock(container).should_receive(:__element_fixed_buffer_size?).and_return(false)
                end
                it "appends new elements to the buffer" do
                    container.push(make_int32(50))
                    container.apply_changes
                    assert_equal [5, 10, 20, 30, 40, 50], container.__buffer.to_str.unpack("Q<l<*")
                end
                it "resets the cached element buffers after an append" do
                    el1 = container.get(1)
                    el4 = container.push(make_int32(50))
                    container.apply_changes
                    assert_same el1, container.get(1)
                    assert_same el4, container.get(4)
                    assert_equal [10, 20, 30, 40, 50], container.map(&:to_simple_value)
                end
                it "removes trailing elements" do
                    container.resize(3)
                    container.apply_changes
                    assert_equal [3, 10, 20, 30], container.__buffer.to_str.unpack("Q<l<*")
                end
                it "resets the cached element buffers after a removal" do
                    el1 = container.get(1)
                    container.resize(3)
                    container.apply_changes
                    assert_same el1, container.get(1)
                    assert_equal [10, 20, 30], container.map(&:to_simple_value)
                end
                it "modifies changed elements" do
                    container.set(1, make_int32(100))
                    assert_equal [4, 10, 20, 30, 40], container.__buffer.to_str.unpack("Q<l<*")
                    container.apply_changes
                    assert_equal [4, 10, 100, 30, 40], container.__buffer.to_str.unpack("Q<l<*")
                end
            end
        end

        describe "#to_simple_value" do
            attr_reader :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            it "returns an array with the converted elements" do
                container.push(make_int32(50))
                assert_equal [10, 20, 30, 40, 50], container.to_simple_value(pack_simple_arrays: false)
            end
            it "returns an array with the converted elements" do
                container.push(make_int32(50))
                expected = Hash[
                    pack_code: "l<",
                    size: 5,
                    data: Base64.strict_encode64([10, 20, 30, 40, 50].pack("l<*"))
                ]
                assert_equal expected, container.to_simple_value(pack_simple_arrays: true)
            end
        end

        describe "#resize" do
            attr_reader :container
            before do
                @container = make_container(10, 20, 30, 40)
            end
            it "removes trailing elements" do
                container.resize(3)
                assert_equal [10, 20, 30], container.map(&:to_ruby)
            end
            it "appends new elements" do
                container.resize(5)
                assert_equal [10, 20, 30, 40, 0], container.map(&:to_ruby)
            end
        end

        describe "#from_ruby" do
            it "initializes the container from the values in the ruby array" do
                container = container_t.new
                container.from_ruby([1, 2, 3, 4])
                assert_equal [4, 1, 2, 3, 4].pack("Q<l<*"), container.to_byte_array
            end
        end

        describe "#to_ruby" do
            describe "character elements" do
                attr_reader :char_t, :vec_char_t, :vec_char
                before do
                    @char_t = registry.create_character '/char', size: 1
                    @vec_char_t = registry.create_container container_m, char_t
                    @vec_char = vec_char_t.from_buffer([4].pack("Q<") + "abcd")
                end
                def make_char(char)
                    char_t.from_buffer(char)
                end

                it "returns a string" do
                    assert_equal "abcd", vec_char.to_ruby
                end
                it "applies size modifications" do
                    vec_char.push make_char('e')
                    assert_equal "abcde", vec_char.to_ruby
                    vec_char.resize(2)
                    assert_equal "ab", vec_char.to_ruby
                end
            end
            describe "elements with pack_code" do
                it "converts to an array with its elements converted themselves" do
                    assert_equal [1, 2, 3],
                        container_t.from_ruby([1, 2, 3]).to_ruby
                end
                it "does not cause the elements to be accessed" do
                    container = container_t.from_ruby([1, 2, 3])
                    flexmock(container).should_receive(:get).never
                    container.to_ruby
                end
                it "applies size modifications" do
                    container = container_t.from_ruby([1, 2, 3])
                    container.push make_int32(4)
                    assert_equal [1, 2, 3, 4], container.to_ruby
                    container = container_t.from_ruby([1, 2, 3])
                    container.resize(2)
                    assert_equal [1, 2], container.to_ruby
                end
            end
            describe "elements without pack code" do
                it "converts to an array with its elements converted themselves" do
                    compound_t = registry.create_compound '/C' do |c|
                        c.add 'a', int32_t
                    end
                    array_t = registry.create_array compound_t, 3

                    assert_equal [Hash['a' => 1], Hash['a' => 2], Hash['a' => 0]],
                        array_t.from_buffer([1, 2, 0].pack("l<*")).to_ruby
                end
            end
        end
    end
end
