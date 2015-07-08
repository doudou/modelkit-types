module TypeStore
    module IO
        # Marshalling/demarshalling of a {Registry} into TypeStore's own XML
        # format
        class IDLExporter
            # Cache of the mapping from a type to its IDL name components
            #
            # This is maintained by {#name_of}. Access directly only to register
            # static mappings
            #
            # @return [Hash<String,(Array<String>,String,String)>] the IDL namespace, the IDL
            #   basename and the IDL type suffix (i.e. array subscripts)
            attr_reader :type_to_idl

            # A mapping from a namespace name to the Namespace object used to
            # represent its generation
            attr_reader :namespaces

            # The list of all instanciated namespace blocks
            attr_reader :all_namespaces

            # A namespace to be prepended to the type's own
            #
            # @return [Array<String>]
            attr_reader :namespace_prefix

            # A namespace to be appended of the type's own
            #
            # @return [Array<String>]
            attr_reader :namespace_suffix

            def self.export(registry, **options)
                new.export(registry, **options)
            end

            def initialize(namespace_prefix: [], namespace_suffix: [])
                @type_to_idl = Hash.new
                @all_namespaces = Array.new
                @namespaces = Hash.new
                @namespace_prefix, @namespace_suffix =
                    namespace_prefix, namespace_suffix
            end

            # Returns the namespace, basename and type suffix (mainly, array
            # subscripts) for the given type
            #
            # @return [(Array<String>,String,String)] the IDL namespace, the IDL
            #   basename and the IDL type suffix (i.e. array subscripts)
            def name_of(type)
                if cached = type_to_idl[type.name]
                    cached
                else
                    namespace, basename, suffix = compute_name_of(type)
                    type_to_idl[type.name] = [namespace, basename, suffix]
                    [namespace, basename, suffix]
                end
            end

            # @api private
            #
            # Helper for {#name_of}. It computes the name components if they are
            # not in the {#type_to_idl} cache
            def compute_name_of(type)
                if type <= ArrayType
                    namespace, basename, suffix = name_of(type.deference)
                    return namespace, basename, "#{suffix}[#{type.length}]"
                elsif type <= ContainerType
                    if type.deference <= ArrayType
                        raise ArgumentError, "cannot build a sequence from an array type"
                    end

                    namespace, * = name_of(type.deference)
                    typedef_name = type.name.gsub(/[^\w]/, "_").gsub(/^_*/, '')
                    if namespace.empty?
                        namespace = namespace_prefix + namespace_suffix
                    end
                    return namespace, typedef_name, ''
                elsif type <= NumericType
                    basename = compute_name_of_numeric(type)
                    return [], basename, ''
                elsif type <= EnumType || type <= CompoundType
                    name_parts = TypeStore.typename_parts(type.name)
                    basename  = name_parts.pop.gsub(/[^\w]/, '_')
                    namespace = name_parts.map { |s| s.gsub(/[^\w]/, '_') }
                    return (namespace_prefix + namespace + namespace_suffix), basename, ''
                else
                    raise ArgumentError, "don't know how to represent #{type} in IDL"
                end
            end

            def compute_name_of_numeric(type)
                if type.integer?
                    if type.size == 1
                        if type.unsigned?
                            return 'octet'
                        else return 'char'
                        end
                    else
                        name =
                            case type.size
                            when 2 then 'short'
                            when 4 then 'long'
                            when 8 then 'long long'
                            else
                                raise ArgumentError, "no IDL equivalent for integer types of size #{type.size}"
                            end
                        if type.unsigned?
                            return "unsigned #{name}"
                        else
                            return name
                        end
                    end
                else
                    case type.size
                    when 4 then return 'float'
                    when 8 then return 'double'
                    else
                        raise ArgumentError, "no IDL equivalent for floating-point types of size #{type.size}"
                    end
                end
            end

            class Namespace
                attr_reader :name, :types, :dependencies
                def initialize(name)
                    @name = name
                    @types = Set.new
                    @dependencies = Set.new
                end

                def depends_on?(namespace_name)
                    dependencies.include?(namespace_name)
                end
            end

            def namespace_of(type)
                namespace_name, _ = name_of(type)
                namespaces[namespace_name] ||= new_namespace_instance(namespace_name)
            end

            def new_namespace_instance(name)
                ns = Namespace.new(name)
                all_namespaces << ns
                namespaces[name] = ns
            end

            def name_all_types(typeset)
                all = typeset.dup.to_set
                typeset.each { |t| all.merge(t.recursive_dependencies) }
                all.each { |t| name_of(t) }
            end

            def export(registry, to: '', opaque_as_any: false, selected: registry.each)
                selected = selected.map do |type_or_name|
                    registry.validate_type_argument(type_or_name)
                end.to_set

                # We have two constraints here:
                #  - the relationship between types (obviously)
                #  - the need to open/close namespaces as little as possible to
                #    workaround bugs in omniorb's IDL generator
                
                current_namespace = Array.new
                selected.each do |type|
                    ns = namespace_of(type)
                    new_ns_dependencies = type.recursive_dependencies.map do |dep_type|
                        next if !selected.include?(dep_type)

                        dep_ns = namespace_of(dep_type)
                        if dep_ns == ns
                        elsif dep_ns.depends_on?(ns.name)
                            new_namespace_instance(ns.name)
                        else dep_ns
                        end
                    end.compact
                    puts "#{type}: #{new_ns_dependencies}"
                    ns.types << type
                    ns.dependencies.merge(new_ns_dependencies)
                end

                emit_namespaces(registry).join("\n")
            end

            def emit_namespaces(registry)
                # Get a global ordering. We will use it only for in-namespace
                # ordering
                global_type_order = Hash.new
                registry.each_type_topological.each_with_index do |type, i|
                    global_type_order[type] = i
                end

                current_ns = Array.new
                emitted_ns = Set.new
                contents = Array.new
                while !all_namespaces.empty?
                    ns = all_namespaces.shift
                    if !ns.dependencies.all? { |dep_ns| emitted_ns.include?(dep_ns) }
                        all_namespaces.push(ns)
                        next
                    end

                    ns_contents = emit_namespace(ns, current_ns, global_type_order)
                    emitted_ns << ns
                    if !ns_contents.empty?
                        contents.concat(emit_namespace_declaration(ns.name, current_ns))
                        contents.concat(ns_contents)
                        current_ns = ns.name
                    end
                end

                contents.concat(emit_namespace_declaration([], current_ns))

                contents
            end

            def emit_namespace_declaration(namespace, current_namespace)
                # Find the common prefix
                i = namespace.each_with_index.find do |part, i|
                    current_namespace[i] != part
                end
                i = (i || [nil, namespace.size]).last
                remove = current_namespace[i..-1]
                add = namespace[i..-1]
                indent = " " * current_namespace.size * 4

                content = Array.new
                remove.size.times do
                    indent = indent[4..-1]
                    content << "#{indent}};"
                end
                add.each do |part|
                    content << "#{indent}module #{part} {"
                    indent = indent + "    "
                end
                content
            end

            def emit_namespace(ns, current_namespace, global_type_order)
                ordered_types = ns.types.sort_by { |t| global_type_order[t] }
                contents = ordered_types.inject(Array.new) do |c, type|
                    c + emit_type(type, ns.name)
                end

                ns.dependencies.clear
                ns.types.clear

                if !contents.empty?
                    indent = "    " * ns.name.size
                    contents.map { |line| "#{indent}#{line}" }
                else Array.new
                end
            end

            def emit_typename(type, current_namespace)
                namespace, basename, * = name_of(type)
                (namespace + [basename]).join("::")
            end

            def suffix_of(type)
                *, suffix = name_of(type)
                suffix
            end

            def emit_type(type, current_namespace)
                if type <= ArrayType || type <= NumericType
                    # We don't emit toplevel built-in and array types
                    return []
                elsif type <= ContainerType
                    namespace, typedef_name, _ = name_of(type)
                    if typedef_name == 'string'
                        return []
                    else
                        return ["typedef sequence<#{emit_typename(type.deference, current_namespace)}> #{typedef_name};"]
                    end
                elsif type <= EnumType
                    _, basename, _ = name_of(type)
                    fields = type.each.map do |symbol, value|
                        "    #{symbol},"
                    end
                    if !fields.empty?
                        # Remove the comma on the last symbol
                        fields[-1] = fields[-1][0..-2]
                    end
                    return ["enum #{basename}", "{", *fields, "};"]
                elsif type <= CompoundType
                    _, basename, _ = name_of(type)
                    fields = type.each.map do |field|
                        field_namespace, field_basename, field_suffix = name_of(field.type)
                        "    #{emit_typename(field.type, current_namespace)} #{field.name}#{suffix_of(field.type)};"
                    end
                    return ["struct #{basename}", "{", *fields, "};"]
                else
                    raise ArgumentError, "don't know how to represent #{type} in IDL"
                end
            end
        end
    end
    Registry::EXPORT_TYPE_HANDLERS['idl'] = IO::IDLExporter
end



