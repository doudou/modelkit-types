require 'modelkit/types/test'

module ModelKit::Types
    describe MetaData do
        it "supports UTF-8 encoding" do
            metadata = MetaData.new
            key = "\u2314"
            value = "\u3421"
            metadata.set(key, value)
            assert_equal [[key, [value].to_set]], metadata.each.to_a
        end
        describe "#set" do
            it "resets all existing values" do
                metadata = MetaData.new
                metadata.add('k', 'v0')
                metadata.add('k', 'v1')
                metadata.set('k', 'v')
                assert_equal ['v'].to_set, metadata.get('k')
            end
            it "accepts multiple arguments" do
                metadata = MetaData.new
                metadata.set('k', 'v0', 'v1')
                assert_equal ['v0', 'v1'].to_set, metadata.get('k')
            end
        end
        describe "#[]=" do
            it "resets all existing values" do
                metadata = MetaData.new
                metadata.add('k', 'v0')
                metadata['k'] = 'v'
                assert_equal ['v'].to_set, metadata.get('k')
            end
        end
        describe "#keys" do
            it "returns all the metadata keys" do
                metadata = MetaData.new
                assert_equal [], metadata.keys
                metadata.add('k0', 'v0')
                assert_equal ['k0'], metadata.keys
                metadata.add('k1', 'v0')
                assert_equal ['k0', 'k1'], metadata.keys
            end
        end
        describe "#pretty_print" do
            it "displays the metadata" do
                metadata = MetaData.new
                metadata.add('k0', 'v0')
                metadata.add('k1', 'v1', 'v2')
                assert_equal <<-EOTEXT, PP.pp(metadata, '')
k0: v0
k1:
- v1
- v2
                EOTEXT

            end
        end
        describe "#include?" do
            it "returns true for an empty entry" do
                metadata = MetaData.new
                metadata.set('k')
                assert metadata.include?('k')
            end
            it "returns true for a non-empty entry" do
                metadata = MetaData.new
                metadata.set('k', 'a')
                assert metadata.include?('k')
            end
            it "returns false for a never-set key" do
                metadata = MetaData.new
                assert !metadata.include?('k')
            end
            it "returns false for a cleared key" do
                metadata = MetaData.new
                metadata.set('k', 'a')
                metadata.clear('k')
                assert !metadata.include?('k')
            end
        end
        describe "#add" do
            it "adds new values to existing ones" do
                metadata = MetaData.new
                metadata.add('k', 'v0')
                assert_equal ['v0'].to_set, metadata.get('k')
                metadata.add('k', 'v1')
                assert_equal ['v0', 'v1'].to_set, metadata.get('k')
            end
            it "accepts multiple arguments" do
                metadata = MetaData.new
                metadata.set('k', 'v')
                metadata.add('k', 'v0', 'v1')
                assert_equal ['v', 'v0', 'v1'].to_set, metadata.get('k')
            end
        end
        describe "#clear" do
            it "clears existing values and removes the key from the key set" do
                metadata = MetaData.new
                metadata.set('k0', 'v0')
                metadata.set('k1', 'v1')
                metadata.clear('k1')
                assert_equal [['k0', ['v0'].to_set]], metadata.each.to_a
            end
            it "clears all values if called without arguments" do
                metadata = MetaData.new
                metadata.set('k0', 'v0')
                metadata.set('k1', 'v1')
                metadata.clear
                assert_equal [], metadata.each.to_a
            end
        end

        describe "#merge" do
            it "adds missing keys" do
                metadata = MetaData.new
                metadata.set('k', 'v')
                m = MetaData.new.merge(metadata)
                assert_equal Hash['k' => ['v'].to_set], m.to_hash
            end
            it "creates completely independent objects" do
                metadata = MetaData.new
                metadata.set('k', 'v')
                m = MetaData.new.merge(metadata)
                refute_same m['k'], metadata['k']
            end
            it "merges existing keys" do
                metadata = MetaData.new
                metadata.set('k', 'v')
                m = MetaData.new
                m.set('k', 'v1', 'v')
                assert_equal Hash['k' => ['v', 'v1'].to_set], m.to_hash
            end
        end
    end
end

