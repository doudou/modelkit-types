require 'rexml/document'

module ModelKit::Types
    module IO
        class XMLImporter
            class Invalid < RuntimeError; end

            def self.import(path, registry: ModelKit::Types::Registry.new)
                new.import(path, registry: registry)
            end

            def import(path, registry: ModelKit::Types::Registry.new)
                document = REXML::Document.new(File.read(path))
                from_xml(document, registry: registry)
            end

            def from_xml(document, registry: ModelKit::Types::Registry.new)
                document.root.each_element do |element|
                    typename = element.attributes['name']
                    case element.name
                    when "numeric"
                        type = registry.create_numeric(typename, **numeric_options(element))
                    when "compound"
                        type = registry.create_compound(typename, **type_options(element)) do |builder|
                            update_compound(builder, element, registry)
                        end
                    when "enum"
                        type = registry.create_enum(typename, **type_options(element)) do |builder|
                            update_enum(builder, element)
                        end
                    when "container"
                        container_model_name = element.attributes['kind']
                        if !registry.has_container_model?(container_model_name)
                            registry.create_container_model(container_model_name)
                        end
                        type = registry.create_container(
                            container_model_name,
                            element.attributes['of'],
                            typename: typename,
                            **type_options(element))
                    when "type"
                        type = registry.create_type(typename, **type_options(element))
                    when 'opaque'
                        type = registry.create_type(typename, **type_options(element, opaque: true))
                    when 'null'
                        type = registry.create_type(typename, **type_options(element, null: true))
                    when 'character'
                        type = registry.create_character(typename, **type_options(element))
                    when "alias"
                        type = registry.create_alias(typename, registry.build(element.attributes['source']))
                        next
                    else
                        raise Invalid, "don't know about the element #{element.name}"
                    end

                    load_metadata(element, type.metadata)
                end
                registry
            end

            def type_options(node, **overrides)
                Hash[size: Integer(node.attributes['size'] || '0'),
                     opaque: node.attributes['opaque'] == '1',
                     null: node.attributes['null'] == '1'].merge(overrides)
            end

            def numeric_options(node)
                Hash[integer: node.attributes['category'] != 'float',
                     unsigned: node.attributes['category'] == 'uint'].
                    merge(type_options(node))
            end

            def update_compound(builder, node, registry)
                node.each_element 'field' do |field_node|
                    field = builder.add(
                        field_node.attributes['name'],
                        field_node.attributes['type'],
                        offset: Integer(field_node.attributes['offset']))

                    load_metadata(field_node, field.metadata)
                end
            end

            def update_enum(type, node)
                node.each_element 'value' do |field_node|
                    type.add field_node.attributes['symbol'].to_sym,
                        Integer(field_node.attributes['value'])
                end
            end

            def load_metadata(element, metadata)
                element.each_element 'metadata' do |meta|
                    metadata.add meta.attributes['key'], meta.cdatas.first.to_s
                end
            end
        end
    end
    Registry::IMPORT_TYPE_HANDLERS['tlb'] = IO::XMLImporter
end

