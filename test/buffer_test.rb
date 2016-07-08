require 'test_helper'

module ModelKit::Types
    describe Buffer do
        describe "#whole?" do
            it "returns true if the buffer is a view on its whole backing buffer" do
                assert Buffer.new("  ").whole?
            end
            it "returns false if the buffer is a partial view on its whole backing buffer" do
                refute Buffer.new("  ", 1, 1).whole?
            end
        end


        describe "#contains?" do
            attr_reader :buffer
            before do
                @buffer = Buffer.new("0123456789")
            end
            it "returns false if self and the argument are not backed by the same string" do
                other = Buffer.new("0123456789", 1, 2)
                refute buffer.contains?(other)
            end
            it "returns false if self's view does not contain its argument" do
                refute buffer.view(1, 2).contains?(buffer.view(2, 2))
            end
            it "returns true if self's view does contain its argument" do
                assert buffer.view(1, 4).contains?(buffer.view(2, 2))
            end
        end

        describe "#empty?" do
            attr_reader :buffer
            before do
                @buffer = Buffer.new("0123456789")
            end
            it "returns true if the buffer size is zero" do
                assert buffer.view(1, 0).empty?
            end
            it "returns false if the buffer size is not zero" do
                refute buffer.view(1, 1).empty?
            end
        end

        describe "#unpack" do
            attr_reader :buffer
            before do
                @buffer = Buffer.new([1, 2, 3].pack("l<*")) # 32-bit signed integers
            end
            it "unpacks backing data at the buffer's offset" do
                assert_equal [2], buffer.view(4, 4).unpack("l<")
            end
        end

        describe "#[]" do
            attr_reader :buffer
            before do
                @buffer = Buffer.new("0123456789", 1, 4)
            end
            it "applies the buffer's offset to the requested access" do
                assert_equal "2", buffer[1]
            end
            it "can return a bigger string" do
                assert_equal "23", buffer[1, 2]
            end
            it "raises RangeError if the index is past-the-end" do
                assert_raises(RangeError) do
                    buffer[4]
                end
            end
            it "raises RangeError if the index is out-of-bounds" do
                assert_raises(RangeError) do
                    buffer[5]
                end
            end
            it "allows offset+size to be past-the-end" do
                assert_equal "4", buffer[3, 1]
            end
            it "raises RangeError if the index+size is out-of-bounds" do
                assert_raises(RangeError) do
                    buffer[1, 4]
                end
            end
        end

        describe "#[]=" do
            attr_reader :backing_buffer, :buffer
            before do
                @backing_buffer = "0123456789"
                @buffer = Buffer.new(backing_buffer, 1, 4)
            end
            it "applies the buffer's offset to the requested access" do
                buffer[1] = "a"
                assert_equal "01a3456789", backing_buffer
                assert_equal "a", buffer[1]
            end
            it "can assign to a range" do
                buffer[1, 2] = "ab"
                assert_equal "ab", buffer[1, 2]
                assert_equal "01ab456789", backing_buffer
            end
            it "raises RangeError if the index is past-the-end" do
                assert_raises(RangeError) do
                    buffer[4] = "a"
                end
                assert_equal "0123456789", backing_buffer
            end
            it "raises RangeError if the index is out-of-bounds" do
                assert_raises(RangeError) do
                    buffer[5] = "a"
                end
                assert_equal "0123456789", backing_buffer
            end
            it "allows offset+size to be past-the-end" do
                buffer[2, 2] = "ab"
                assert_equal "012ab56789", backing_buffer
            end
            it "raises RangeError if the index+size is out-of-bounds" do
                assert_raises(RangeError) do
                    buffer[1, 4] = "c"
                end
                assert_equal "0123456789", backing_buffer
            end
        end

        describe "#view" do
            attr_reader :buffer
            before do
                @buffer = Buffer.new("0123456789", 1, 5)
            end

            it "returns a buffer that represents a view of the original buffer" do
                view  = buffer.view(2, 2)
                assert_same view.backing_buffer, buffer.backing_buffer
                assert_equal "34", view.to_str
            end
            it "raises RangeError if the index is past-the-end" do
                assert_raises(RangeError) do
                    buffer.view(5, 1)
                end
            end
            it "raises RangeError if the index is out-of-bounds" do
                assert_raises(RangeError) do
                    buffer.view(6, 1)
                end
            end
            it "allows offset+size to be past-the-end" do
                view = buffer.view(3, 2)
                assert_same view.backing_buffer, buffer.backing_buffer
                assert_equal "45", view.to_str
            end
            it "raises RangeError if the index+size is out-of-bounds" do
                assert_raises(RangeError) do
                    buffer.view(2, 4)
                end
            end
        end

        describe "#slice!" do
            attr_reader :buffer
            before do
                @buffer = Buffer.new("0123456789")
            end

            it "removes the requested byte range from the backing buffer" do
                buffer.slice!(2, 2)
                assert_equal "01456789", buffer.backing_buffer
            end
            it "updates the size" do
                buffer.slice!(2, 2)
                assert_equal 8, buffer.size
            end
            it "raises RangeError if the offset is negative" do
                assert_raises(RangeError) do
                    buffer.slice!(-1, 2)
                end
            end
            it "does nothing if the offset is past-the-end and size is zero" do
                buffer.slice!(10, 0)
                assert_equal "0123456789", buffer.backing_buffer
            end
            it "raises RangeError if the offset is beyond the end of buffer" do
                assert_raises(RangeError) do
                    buffer.slice!(11, 2)
                end
            end
            it "raises RangeError if the range crosses the end of buffer" do
                assert_raises(RangeError) do
                    buffer.slice!(9, 2)
                end
            end
        end

        describe "#to_str" do
            it "returns the string that represents the buffer's content" do
                buffer = Buffer.new("0123456789", 1, 4)
                assert_equal "1234", buffer.to_str
            end
        end

        describe "#copy_to" do
            attr_reader :backing_buffer, :buffer
            before do
                @backing_buffer = "0123456789"
                @buffer = Buffer.new(backing_buffer, 1, 4)
            end
            it "copies the data to the target buffer" do
                source_buffer = Buffer.new("abcdefghi", 3, 4)
                source_buffer.copy_to(buffer)
                assert_equal "0defg56789", backing_buffer
            end
            it "raises RangeError if the two buffers do not have the same size" do
                source_buffer = Buffer.new("abcdefghi", 3, 10)
                assert_raises(RangeError) do
                    source_buffer.copy_to(buffer)
                end
                assert_equal "0123456789", backing_buffer
            end
        end

        it "has defined #to_types_buffer on a string to convert it into a buffer" do
            str = "01234".dup
            buffer = str.to_types_buffer
            assert_same str, buffer.backing_buffer
            assert_equal 0, buffer.offset
            assert_equal 5, buffer.size
        end
    end
end
