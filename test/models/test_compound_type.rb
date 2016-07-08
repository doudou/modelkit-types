require 'modelkit/types/test'
require 'pp'

module ModelKit::Types
    module Models
        describe CompoundType do
            attr_reader :compound_t, :field_t
            before do
                @field_t = ModelKit::Types::Type.new_submodel(typename: '/field_t', size: 10)
                @compound_t = ModelKit::Types::CompoundType.new_submodel(typename: '/compound_t', size: 10)
            end

            it "has a name" do
                assert_equal "ModelKit::Types::CompoundType", ModelKit::Types::CompoundType.name
            end
            it "has a metadata object" do
                assert ModelKit::Types::CompoundType.metadata
            end

            describe "#add" do
                it "raises if the first field is not at offset zero" do
                    assert_raises(ArgumentError) do
                        compound_t.add 'f0', field_t, offset: 10
                    end
                end
                it "passes if the first field's offset is explicitely given as zero" do
                    compound_t.add 'f0', field_t, offset: 0
                end
                it "adds a field to #fields" do
                    compound_t.add 'f0', field_t
                    assert(field = compound_t.get('f0'))
                    assert_equal 'f0', field.name
                    assert_same field_t, field.type
                end
                it "stores the computed offset if not specified explicitely" do
                    compound_t.add 'f0', field_t
                    assert_equal 0, compound_t.get('f0').offset
                    compound_t.add 'f1', field_t, offset: 15
                    assert_equal 15, compound_t.get('f1').offset
                    compound_t.add 'f2', field_t
                    assert_equal 25, compound_t.get('f2').offset
                end
                it "sets the fields' skip based on the difference between the last and new offset" do
                    compound_t.add 'f0', field_t
                    assert_equal 0, compound_t.get('f0').skip
                    compound_t.add 'f1', field_t, offset: 10
                    assert_equal 0, compound_t.get('f1').skip
                    compound_t.add 'f2', field_t, offset: 25
                    assert_equal 5, compound_t.get('f1').skip
                end
                it "can set the fields skip explicitely" do
                    compound_t.add 'f0', field_t
                    assert_equal 0, compound_t.get('f0').skip
                    compound_t.add 'f1', field_t, skip: 5
                    assert_equal 5, compound_t.get('f1').skip
                    assert_equal 10, compound_t.get('f1').offset
                    compound_t.add 'f2', field_t, skip: 10
                    assert_equal 25, compound_t.get('f2').offset
                    assert_equal 10, compound_t.get('f2').skip
                end
                it "raises DuplicateFieldError if the field already exists" do
                    compound_t.add 'f0', field_t
                    assert_raises(DuplicateFieldError) { compound_t.add 'f0', field_t }
                end
                it "raises NotFromThisRegistryError if the field is not from the same registry than self" do
                    field_t = ModelKit::Types::Type.new_submodel registry: Registry.new
                    assert_raises(NotFromThisRegistryError) { compound_t.add 'f0', field_t }
                end
                it "does not set #fixed_buffer_size to false if the field is of fixed size" do
                    compound_t.add 'f0', field_t
                    assert compound_t.fixed_buffer_size?
                end
                it "does not reset #fixed_buffer_size once it is false" do
                    flexmock(field_t).should_receive(:fixed_buffer_size?).and_return(false)
                    compound_t.add 'f0', field_t
                    compound_t.add 'f1', ModelKit::Types::Type.new_submodel
                    assert !compound_t.fixed_buffer_size?
                end
                it "sets #fixed_buffer_size to false if the field is of variable size" do
                    flexmock(field_t).should_receive(:fixed_buffer_size?).and_return(false)
                    compound_t.add 'f0', field_t
                    assert !compound_t.fixed_buffer_size?
                end
                it "sets #contains_opaques if the new field is an opaque" do
                    flexmock(field_t).should_receive(:opaque?).and_return(true)
                    compound_t.add 'f0', field_t
                    assert compound_t.contains_opaques?
                end
                it "sets #contains_opaques if the new field contains opaques" do
                    flexmock(field_t).should_receive(:contains_opaques?).and_return(true)
                    compound_t.add 'f0', field_t
                    assert compound_t.contains_opaques?
                end
                it "does not set #contains_opaques? for non-opaque fields" do
                    compound_t.add 'f0', field_t
                    assert !compound_t.contains_opaques?
                end
                it "does not reset #contains_opaques? once it is set" do
                    flexmock(field_t).should_receive(:contains_opaques?).and_return(true)
                    compound_t.add 'f0', field_t
                    compound_t.add 'f1', ModelKit::Types::Type.new_submodel
                    assert compound_t.contains_opaques?
                end
                it "registers the field type as a direct dependency" do
                    flexmock(compound_t).should_receive(:add_direct_dependency).with(field_t).once
                    compound_t.add 'f', field_t
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

            describe "#[]" do
                it "returns the type of the field" do
                    field = compound_t.add('f0', field_t)
                    assert_same field_t, compound_t['f0']
                end
                it "raises FieldNotFound if the field does not exist" do
                    assert_raises(FieldNotFound) { compound_t.get('f0') }
                end
            end

            describe "#get" do
                it "returns the field object" do
                    field = compound_t.add('f0', field_t)
                    assert_same field, compound_t.get('f0')
                end
                it "raises FieldNotFound if the field does not exist" do
                    assert_raises(FieldNotFound) { compound_t.get('f0') }
                end
            end

            describe "#has_field?" do
                it "returns true if the field exists" do
                    compound_t.add('f0', field_t)
                    assert compound_t.has_field?('f0')
                end
                it "raises FieldNotFound if the field does not exist" do
                    assert !compound_t.has_field?('f0')
                end
            end

            describe "#each" do
                it "enumerates the fields by object" do
                    f0 = compound_t.add('f0', field_t)
                    f1 = compound_t.add('f1', field_t, offset: 20)
                    assert_equal [f0, f1].to_set, compound_t.each.to_set
                end
            end

            describe "#to_h" do
                attr_reader :f0_t, :f1_t
                before do
                    f0_t = @f0_t = ModelKit::Types::Type.new_submodel typename: '/int32_t'
                    f1_t = @f1_t = ModelKit::Types::Type.new_submodel typename: '/float'
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
                    field = compound_t.add 'f', field_t
                    field.metadata.set('doc', 'documentation string')
                    pp = PP.new('')
                    compound_t.pretty_print(pp, verbose: true)
                end
                it "does not raise" do
                    field = compound_t.add 'f', field_t
                    field.metadata.set('doc', 'documentation string')
                    pp = PP.new('')
                    compound_t.pretty_print(pp, verbose: false)
                end
            end

            describe "#direct_dependencies" do
                it "lists the field types" do
                    compound_t.add('f0', field_t)
                    assert_equal [field_t].to_set, compound_t.direct_dependencies
                end
            end

            describe "marshalling and unmarshalling" do
                it "marshals and unmarshals metadata" do
                    f = compound_t.add('f0', field_t)
                    Registry.new.register(compound_t)
                    f.metadata.set('k0', 'v0')
                    new_registry = ModelKit::Types::Registry.from_xml(compound_t.to_xml)
                    assert_equal [['k0', ['v0'].to_set]], new_registry.get('/compound_t').get('f0').metadata.each.to_a
                end
            end

            describe "#validate_merge" do
                attr_reader :other_t
                before do
                    @other_t = ModelKit::Types::CompoundType.new_submodel(typename: '/compound_t', size: 10)
                end
                it "passes if two fields with the same name have different types with the same name" do
                    compound_t.add('f0', field_t, offset: 0)
                    other_t.add('f0', ModelKit::Types::Type.new_submodel(typename: '/field_t'), offset: 0)
                    other_t.validate_merge(compound_t)
                end
                it "raises if two fields with the same name have types with different names" do
                    compound_t.add('f0', field_t, offset: 0)
                    other_t.add('f0', ModelKit::Types::Type.new_submodel(typename: 'field'), offset: 0)
                    assert_raises(MismatchingFieldTypeError) { other_t.validate_merge(compound_t) }
                end
                it "raises if two fields with the same name have different offets" do
                    compound_t.add('f0', field_t, offset: 0)
                    compound_t.add('test', field_t, offset: 20)
                    other_t.add('f0', field_t, offset: 0)
                    other_t.add('test', field_t, offset: 25)
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
                attr_reader :target_registry
                before do
                    @target_registry = Registry.new
                end

                it "copies the metadata over" do
                    f = compound_t.add('f0', field_t, offset: 0)
                    f.metadata.set('k', 'v')
                    compound_t.copy_to(target_registry)
                    other_t = target_registry.get('/compound_t')
                    other_f = other_t.get('f0')
                    assert_equal [['k', ['v'].to_set]], other_f.metadata.each.to_a
                end
                it "reuses an existing field type existing on the target" do
                    target_field_t = field_t.copy_to(target_registry)
                    compound_t.add('f0', field_t, offset: 0)
                    target_t = compound_t.copy_to(target_registry)
                    assert_same target_field_t, target_t.get('f0').type
                end
            end

            describe "#merge" do
                attr_reader :other_t
                before do
                    @other_t = ModelKit::Types::CompoundType.new_submodel(typename: 'compound_t', size: 10)
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
                    compound_t.add('f0', field_t, offset: 0)
                    other_f = other_t.add('f0', field_t, offset: 0)
                    other_t.merge(compound_t)
                    assert !other_f.has_metadata?
                end
                it "does not create a field metadata object if the merged field does not have one" do
                    compound_t.add('f0', field_t, offset: 0)
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

            describe "#casts_to?" do
                attr_reader :subject, :field_t
                before do
                    @subject = ModelKit::Types::CompoundType.new_submodel
                    @field_t = ModelKit::Types::Type.new_submodel
                end

                it 'returns true if given itself' do
                    subject.add 'f', field_t, offset: 0
                    assert subject.casts_to?(subject)
                end

                it "returns true if given a type towards which its first field can cast to" do
                    subject.add 'f', field_t, offset: 0
                    test_t = flexmock
                    flexmock(field_t).should_receive(:casts_to?).with(test_t).and_return(true)
                    assert subject.casts_to?(test_t)
                end

                it "returns false if given a type its first field cannot be cast to" do
                    subject.add 'f', field_t, offset: 0
                    test_t = flexmock
                    flexmock(field_t).should_receive(:casts_to?).with(test_t).and_return(false)
                    assert !subject.casts_to?(test_t)
                end
            end

            describe "#==" do
                attr_reader :field_t, :compound_t, :other_t
                before do
                    @field_t = ModelKit::Types::Type.new_submodel(typename: '/field_t', size: 10)
                    @compound_t = ModelKit::Types::CompoundType.new_submodel(typename: '/compound_t', size: 10)
                    @other_t = ModelKit::Types::CompoundType.new_submodel(typename: '/compound_t', size: 10)
                end

                it "returns true when comparing with itself" do
                    compound_t.add 'f0', field_t
                    compound_t.add 'f1', field_t, skip: 5
                    compound_t.add 'f2', field_t
                    assert(compound_t == compound_t)
                end
                it "returns false when compared with an arbitrary object" do
                    refute(compound_t == Object.new)
                end
                it "returns true when comparing two empty compounds" do
                    other_t = ModelKit::Types::CompoundType.new_submodel(typename: '/compound_t', size: 10)
                    assert(compound_t == other_t)
                end
                it "returns false if the field placement is different" do
                    compound_t.add 'f0', field_t
                    compound_t.add 'f1', field_t, skip: 5
                    compound_t.add 'f2', field_t
                    other_t.add 'f0', field_t, skip: 2
                    other_t.add 'f1', field_t, skip: 3
                    other_t.add 'f2', field_t
                    refute(compound_t == other_t)
                end
                it "returns false if argument has less fields" do
                    compound_t.add 'f0', field_t
                    compound_t.add 'f1', field_t, skip: 5
                    compound_t.add 'f2', field_t
                    other_t.add 'f0', field_t
                    other_t.add 'f1', field_t, skip: 5
                    refute(compound_t == other_t)
                end
                it "returns false if argument has more fields" do
                    compound_t.add 'f0', field_t
                    compound_t.add 'f1', field_t, skip: 5
                    other_t.add 'f0', field_t
                    other_t.add 'f1', field_t, skip: 5
                    other_t.add 'f2', field_t
                    refute(compound_t == other_t)
                end
                it "returns false if the field types are different" do
                    other_field_t = ModelKit::Types::NumericType.new_submodel(typename: '/other_field_t', size: 10)
                    compound_t.add 'f0', field_t
                    compound_t.add 'f1', field_t, skip: 5
                    compound_t.add 'f2', field_t
                    other_t.add 'f0', field_t
                    other_t.add 'f1', other_field_t, skip: 5
                    other_t.add 'f2', field_t
                    refute(compound_t == other_t)
                end
                it "returns false if the field names are different" do
                    other_field_t = ModelKit::Types::NumericType.new_submodel(typename: '/other_field_t', size: 10)
                    compound_t.add 'f0', field_t
                    compound_t.add 'f1', field_t, skip: 5
                    compound_t.add 'f2', field_t
                    other_t.add 'f0', field_t
                    other_t.add 'test', other_field_t, skip: 5
                    other_t.add 'f2', field_t
                    refute(compound_t == other_t)
                end
            end
        end
    end
end

