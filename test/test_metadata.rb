require 'typestore/test'

module TypeStore
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

        it "can be accessed for fields" do
            assert_kind_of Typelib::MetaData, type.field_metadata['field']
        end
        it "is marshalled and unmarshalled" do
            type.field_metadata['field'].set('k0', 'v0')
            new_registry = Typelib::Registry.from_xml(registry.to_xml)
            assert_equal [['k0', ['v0']]].to_set, new_registry.get('/Test').field_metadata['field'].each.to_a
        end
    end
end

