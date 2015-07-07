require 'typestore/test'

module TypeStore
    module Models
        describe CompoundType do
            attr_reader :compound_t, :field_t
            before do
                @field_t = TypeStore::Type.new_submodel(typename: '/field_t', size: 10)
                @compound_t = TypeStore::CompoundType.new_submodel(typename: '/compound_t', size: 10)
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
                it "raises NotFromThisRegistryError if the field is not from the same registry than self" do
                    field_t = TypeStore::Type.new_submodel registry: Registry.new
                    assert_raises(NotFromThisRegistryError) { compound_t.add 'f0', field_t }
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

            describe "#direct_dependencies" do
                it "lists the field types" do
                    compound_t.add('f0', field_t, offset: 10)
                    assert_equal [field_t].to_set, compound_t.direct_dependencies
                end
            end

            describe "marshalling and unmarshalling" do
                it "marshals and unmarshals metadata" do
                    f = compound_t.add('f0', field_t, offset: 10)
                    compound_t.register(Registry.new)
                    f.metadata.set('k0', 'v0')
                    new_registry = TypeStore::Registry.from_xml(compound_t.to_xml)
                    assert_equal [['k0', ['v0'].to_set]], new_registry.get('/compound_t').get('f0').metadata.each.to_a
                end
            end

            describe "#validate_merge" do
                attr_reader :other_t
                before do
                    @other_t = TypeStore::CompoundType.new_submodel(typename: '/compound_t', size: 10)
                end
                it "passes if two fields with the same name have different types with the same name" do
                    compound_t.add('f0', field_t, offset: 0)
                    other_t.add('f0', TypeStore::Type.new_submodel(typename: '/field_t'), offset: 0)
                    other_t.validate_merge(compound_t)
                end
                it "raises if two fields with the same name have types with different names" do
                    compound_t.add('f0', field_t, offset: 0)
                    other_t.add('f0', TypeStore::Type.new_submodel(typename: 'field'), offset: 0)
                    assert_raises(MismatchingFieldTypeError) { other_t.validate_merge(compound_t) }
                end
                it "raises if two fields with the same name have different offets" do
                    compound_t.add('f0', field_t, offset: 0)
                    other_t.add('f0', field_t, offset: 10)
                    assert_raises(MismatchingFieldOffsetError) { other_t.validate_merge(compound_t) }
                end
                it "raises if self has a field that the argument does not" do
                    compound_t.add('f0', field_t, offset: 0)
                    compound_t.add('f1', field_t, offset: 10)
                    other_t.add('f0', field_t, offset: 0)
                    assert_raises(MismatchingFieldSetError) { other_t.validate_merge(compound_t) }
                end
                it "raises if the argument has a field that self does not" do
                    compound_t.add('f0', field_t, offset: 0)
                    other_t.add('f0', field_t, offset: 0)
                    other_t.add('f1', field_t, offset: 10)
                    assert_raises(MismatchingFieldSetError) { other_t.validate_merge(compound_t) }
                end
            end

            describe "#copy_to" do
                it "copies the metadata over" do
                    f = compound_t.add('f0', field_t, offset: 0)
                    f.metadata.set('k', 'v')
                    reg = Registry.new
                    compound_t.copy_to(reg)
                    other_t = reg.get('/compound_t')
                    other_f = other_t.get('f0')
                    assert_equal [['k', ['v'].to_set]], other_f.metadata.each.to_a
                end
            end

            describe "#merge" do
                attr_reader :other_t
                before do
                    @other_t = TypeStore::CompoundType.new_submodel(typename: 'compound_t', size: 10)
                end
                it "merges the field's metadata" do
                    f = compound_t.add('f0', field_t, offset: 0)
                    f.metadata.set('k', 'v')
                    other_f = other_t.add('f0', field_t, offset: 0)
                    flexmock(other_f.metadata).should_receive(:merge).with(f.metadata).once.
                        pass_thru
                    other_t.merge(compound_t)
                    assert_equal [['k', ['v'].to_set]], other_f.metadata.each.to_a
                end
                it "does not create a field metadata object if the merged field does not have one" do
                    f = compound_t.add('f0', field_t, offset: 0)
                    other_f = other_t.add('f0', field_t, offset: 0)
                    other_t.merge(compound_t)
                    assert !other_f.has_metadata?
                end
                it "does not create a field metadata object if the merged field does not have one" do
                    f = compound_t.add('f0', field_t, offset: 0)
                    other_f = other_t.add('f0', field_t, offset: 0)
                    other_t.merge(compound_t)
                    assert !other_f.instance_variable_get(:@metadata)
                end
                it "does not create a field metadata object if the merged field as an empty one" do
                    f = compound_t.add('f0', field_t, offset: 0)
                    f.metadata # Create an empty metadata object
                    other_f = other_t.add('f0', field_t, offset: 0)
                    other_t.merge(compound_t)
                    assert !other_f.instance_variable_get(:@metadata)
                end
            end

            describe "#apply_resize" do
                it "shifts subsequent fields" do
                    f0 = compound_t.add 'f0', field_t, offset: 0
                    f1 = compound_t.add 'f1', field_t, offset: field_t.size
                    compound_t.apply_resize(field_t => field_t.size * 2)
                    assert_equal 0, f0.offset
                    assert_equal field_t.size * 2, f1.offset
                end
                it "does not touch fields that are beyond the necessary offset" do
                    f0 = compound_t.add 'f0', field_t, offset: 0
                    f1 = compound_t.add 'f1', field_t, offset: field_t.size
                    f2 = compound_t.add 'f2', field_t, offset: field_t.size * 5
                    compound_t.apply_resize(field_t => field_t.size * 2)
                    assert_equal 0, f0.offset
                    assert_equal field_t.size * 2, f1.offset
                    assert_equal field_t.size * 5, f2.offset
                end
            end
        end
    end
end

