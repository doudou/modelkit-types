require 'typestore/test'

module TypeStore
    module Models
        describe CompoundType do
            attr_reader :compound_t, :field_t
            before do
                @field_t = TypeStore::Type.new_submodel(typename: 'field_t', size: 10)
                @compound_t = TypeStore::CompoundType.new_submodel(typename: 'compound_t', size: 10)
            end

            describe "#add" do
                it "adds a field to #fields" do
                    compound_t.add 'f0', field_t
                    assert(field = compound_t.fields['f0'])
                    assert_equal 'f0', field.name
                    assert_same field_t, field.type
                end
                it "sets the fields' offset" do
                    compound_t.add 'f0', field_t, offset: 10
                    assert_equal 10, compound_t.fields['f0'].offset
                end
                it "raises DuplicateFieldError if the field already exists" do
                    compound_t.add 'f0', field_t
                    assert_raises(DuplicateFieldError) { compound_t.add 'f0', field_t }
                end
            end

            describe "#empty?" do
                it "returns true if there are no fields" do
                    assert compound_t.empty?
                end
                it "returns false if there are fields" do
                    compound_t.add 'f0', field_t
                    assert !compound_t.empty?
                end
            end

            describe "#offset_of" do
                it "returns the offset value of a field" do
                    compound_t.add 'f0', field_t, offset: 10
                    assert_equal 10, compound_t.offset_of('f0')
                end
                it "raises FieldNotFound if the field does not exist" do
                    assert_raises(FieldNotFound) { compound_t.offset_of('f0') }
                end
            end

            describe "#get" do
                it "returns the field object" do
                    field = compound_t.add('f0', field_t, offset: 10)
                    assert_same field, compound_t.get('f0')
                end
                it "raises FieldNotFound if the field does not exist" do
                    assert_raises(FieldNotFound) { compound_t.get('f0') }
                end
            end

            describe "#has_field?" do
                it "returns true if the field exists" do
                    compound_t.add('f0', field_t, offset: 10)
                    assert compound_t.has_field?('f0')
                end
                it "raises FieldNotFound if the field does not exist" do
                    assert !compound_t.has_field?('f0')
                end
            end

            describe "#each" do
                it "enumerates the fields by object" do
                    f0 = compound_t.add('f0', field_t, offset: 10)
                    f1 = compound_t.add('f1', field_t, offset: 20)
                    assert_equal [f0, f1].to_set, compound_t.each.to_set
                end
            end

            describe "#each_field" do
                it "enumerates the fields by name and type" do
                    f0 = compound_t.add('f0', (f0_t = TypeStore::Type.new_submodel), offset: 10)
                    f1 = compound_t.add('f1', (f1_t = TypeStore::Type.new_submodel), offset: 20)
                    assert_equal [['f0', f0_t], ['f1', f1_t]].to_set, compound_t.each_field.to_set
                end
            end

            describe "#to_h" do
                attr_reader :f0_t, :f1_t
                before do
                    f0_t = @f0_t = TypeStore::Type.new_submodel typename: '/int32_t'
                    f1_t = @f1_t = TypeStore::Type.new_submodel typename: '/float'
                    compound_t.add 'f0', f0_t, offset: 0
                    compound_t.add 'f1', f1_t, offset: 100
                end

                it "describes the type" do
                    expected = Hash[class: 'CompoundType',
                                    name: compound_t.name,
                                    fields: [
                                        Hash[name: 'f0', type: f0_t.to_h_minimal(layout_info: false)],
                                        Hash[name: 'f1', type: f1_t.to_h_minimal(layout_info: false)]
                                    ]]
                    assert_equal expected, compound_t.to_h(layout_info: false, recursive: false)
                end

                it "describes the sub-type fully if recursive is true" do
                    expected = Hash[class: 'CompoundType',
                                    name: compound_t.name,
                                    fields: [
                                        Hash[name: 'f0', type: f0_t.to_h(layout_info: false)],
                                        Hash[name: 'f1', type: f1_t.to_h(layout_info: false)]
                                    ]]
                    assert_equal expected, compound_t.to_h(layout_info: false, recursive: true)
                end

                it "adds the field offsets if layout_info is true" do
                    expected = Hash[class: 'CompoundType',
                                    name: compound_t.name,
                                    size: compound_t.size,
                                    fields: [
                                        Hash[name: 'f0', type: f0_t.to_h_minimal(layout_info: true), offset: 0],
                                        Hash[name: 'f1', type: f1_t.to_h_minimal(layout_info: true), offset: 100]
                                    ]]
                    assert_equal expected, compound_t.to_h(layout_info: true, recursive: false)
                end
            end

            describe "#pretty_print" do
                it "does not raise" do
                    compound_t.add 'f', field_t, offset: 10
                    PP.pp(compound_t, StringIO.new)
                end
            end

            describe "marshalling and unmarshalling" do
                it "marshals and unmarshals metadata" do
                    f = compound_t.add('f0', field_t, offset: 10)
                    f.metadata.set('k0', 'v0')
                    new_registry = TypeStore::Registry.from_xml(compound_t.to_xml)
                    assert_equal [['k0', ['v0']]].to_set, new_registry.get('/Test').get('field').metadata.each.to_a
                end
            end
        end
    end
end

