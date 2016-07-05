require 'modelkit/types/test'

module ModelKit::Types
    describe Buffer do
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

        describe "#slice" do
            attr_reader :buffer
            before do
                @buffer = Buffer.new("0123456789", 1, 5)
            end

            it "returns a buffer that represents a slice of the original buffer" do
                slice  = buffer.slice(2, 2)
                assert_same slice.backing_buffer, buffer.backing_buffer
                assert_equal "34", slice.to_str
            end
            it "raises RangeError if the index is past-the-end" do
                assert_raises(RangeError) do
                    buffer.slice(5, 1)
                end
            end
            it "raises RangeError if the index is out-of-bounds" do
                assert_raises(RangeError) do
                    buffer.slice(6, 1)
                end
            end
            it "allows offset+size to be past-the-end" do
                slice = buffer.slice(3, 2)
                assert_same slice.backing_buffer, buffer.backing_buffer
                assert_equal "45", slice.to_str
            end
            it "raises RangeError if the index+size is out-of-bounds" do
                assert_raises(RangeError) do
                    buffer.slice(2, 4)
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
    end
end
