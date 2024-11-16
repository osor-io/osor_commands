#import "Basic";
#import "String";
#import "Math";
#import "Sort";
#import "Hash_Table";
#import "Compiler";
#import "Atomics";
#import "osor_tokenizer"; // https:/github.com/osor-io/osor_tokenizer



#module_parameters(COMMAND_ANNOTATION := "Command");



execute_command :: (command_string : string) -> success : bool, results : []Any, message : string
{
    init_if_needed();
    parse_success, name, arguments, parse_message := parse_command_string(command_string);
    if !parse_success
    {
        return false, .[], tprint("Couldn't parse command string %: %", command_string, parse_message);
    }
    command := table_find_pointer(*__command_table, name);
    if !command
    {
        return false, .[], tprint("Couldn't find command %", name);
    }
    success, result, message := command.*(arguments);
    return success, result, message;
}



is_command :: (name : string) -> bool
{
    init_if_needed();
    command := table_find_pointer(*__command_table, name);
    return command != null;
}



get_all_commands :: () -> []Command_Data
{
    init_if_needed();
    return __command_data;
}



Command_Procedure :: #type (arguments : []Any) -> (success : bool, results : []Any, message: string);
Command_Data :: struct
{
    name : string;
    name_with_hints : string;
    command : Command_Procedure;
}



__command_data : [..]Command_Data;
__command_table : Table(string, Command_Procedure);
__register_command :: (name : string, command : Command_Procedure, name_with_hints : string)
{
    array_add(*__command_data, .{
        name = name,
        command = command,
        name_with_hints = name_with_hints,
    });
    table_add(*__command_table, name, command);
}



__update_stuff_after_registering_a_bunch_of_commands :: ()
{
    quick_sort(__command_data, (a : Command_Data, b : Command_Data) -> int
    {
        return compare_strings(a.name, b.name);
    });
}



__commands_any_to_arg :: (arg : Any, $T : Type) -> value : T #expand
{
    //
    // @@NOTE: The types expected in arg are the ones that
    // parse_command_string(...) will add to the array in the first
    // place, that's why we can check explicitly for art.type to
    // be s64 or float64.
    //
    #if type_info(T).type == .INTEGER
    {
        if arg.type == type_info(s64)
        {
            value_s64 := (cast(*s64)arg.value_pointer).*;
            #if T ==
            {
                case u8;  MIN :: 0;       MAX :: U8_MAX;
                case u16; MIN :: 0;       MAX :: U16_MAX;
                case u32; MIN :: 0;       MAX :: U32_MAX;
                case u64; MIN :: 0;       MAX :: U64_MAX;
                case s8;  MIN :: S8_MIN;  MAX :: S8_MAX;
                case s16; MIN :: S16_MIN; MAX :: S16_MAX;
                case s32; MIN :: S32_MIN; MAX :: S32_MAX;
                case s64; MIN :: S64_MIN; MAX :: S64_MAX;
                case; #assert(false);
            }
            if value_s64 >= MIN && value_s64 <= MAX
            {
                return cast(T)value_s64;
            }
            else
            {
                `return false, .[], tprint("Integer provided (%) doesn't fit in expected type % [%,%]", value_s64, T, MIN, MAX);
            }
        }
        `return false, .[], tprint("Error parsing argument, expected a % and got a %", T, type_to_string(arg.type));
    }
    else #if type_info(T).type == .FLOAT
    {
        value_f64 : float64;
        if arg.type == type_info(s64)
        {
            value_s64 := (cast(*s64)arg.value_pointer).*;
            value_f64 = xx value_s64;
        }
        else if arg.type == type_info(float64)
        {
            value_f64 = (cast(*float64)arg.value_pointer).*;
        }
        else
        {
            `return false, .[], tprint("Error parsing argument, expected a % and got a %", T, type_to_string(arg.type));
        }
        return cast(T)value_f64;
    }
    else #if T == bool
    {
        if arg.type == type_info(bool)
        {
            return (cast(*bool)arg.value_pointer).*;
        }
        `return false, .[], tprint("Error parsing argument, expected a % and got a %", T, type_to_string(arg.type));
    }
    else #if T == string
    {
        if arg.type == type_info(string)
        {
            return (cast(*string)arg.value_pointer).*;
        }
        `return false, .[], tprint("Error parsing argument, expected a % and got a %", T, type_to_string(arg.type));
    }
    else #if type_info(T).type == .ENUM
    {
        if arg.type == type_info(string)
        {
            the_string := (cast(*string)arg.value_pointer).*;
            enum_info := type_info(T);
            for enum_info.names 
            {
                if equal_nocase(it, the_string)
                {
                    value := cast(T)enum_info.values[it_index];
                    return value;
                }
            }
        }
        `return false, .[], tprint("Error parsing argument, expected a % and got a %", T, type_to_string(arg.type));
    }
    else #if type_info(T).type == .POINTER
    {
        pointer : T;
        pointer = New(type_of(pointer.*),,temp);
        pointer.* = __commands_any_to_arg(arg, type_of(pointer.*));
        return pointer;
    }
    else
    {
        #run compiler_report(tprint("Type % (a %) is not supported as an argument to a command", T, type_info(T).type));
    }
}



__commands_temporary_copy :: (v : $T) -> Any
{
    copy := cast(*T)talloc(size_of(T));
    copy.* = v;
    result : Any;
    result.type = type_info(T);
    result.value_pointer = copy;
    return result;
}



Commands_Metaprogram_Plugin :: struct
{
    using #as plugin : Metaprogram_Plugin;
    found_module := false;
    round := 0;
    commands_to_add : [..] *Code_Procedure_Header;
}

get_plugin :: () -> *Metaprogram_Plugin #compile_time
{
    plugin := New(Commands_Metaprogram_Plugin);
    plugin.message = handle_plugin_message;
    plugin.finish = (plugin : *Metaprogram_Plugin)
    {
        commands_plugin := cast(*Commands_Metaprogram_Plugin)plugin;
        if !commands_plugin.found_module
        {
            compiler_report(tprint("Using the osor_commands plug-in but we didn't see an #import for the module, you need it both as a module and a plug-in!"));
        }
    };
    plugin.shutdown = (plugin : *Metaprogram_Plugin)
    {
        commands_plugin := cast(*Commands_Metaprogram_Plugin)plugin;
        array_reset(*commands_plugin.commands_to_add);
        free(commands_plugin);
    };
    plugin.log_help = (plugin : *Metaprogram_Plugin)
    {
        log("Tag procedures with @Command which you can then execute from a string via command_execute(...)");
    };
    return plugin;
}



#scope_file



handle_plugin_message :: (plugin : *Metaprogram_Plugin, message: *Message) #compile_time
{
    commands_plugin := cast(*Commands_Metaprogram_Plugin)plugin;

    if message.kind ==
    {
        case .IMPORT;
        message_import := cast(*Message_Import)message;
        if !commands_plugin.found_module && message_import.module_name == "osor_commands"
        {
            commands_plugin.found_module = true;
            add_build_string("OSOR_COMMANDS_PLUGIN_HAS_RUN :: true;", plugin.workspace, message_import);
        }

        case .TYPECHECKED;
        message_typechecked := cast(*Message_Typechecked)message;
        for typechecked_procedure_header : message_typechecked.procedure_headers
        {
            code_header : *Code_Procedure_Header = typechecked_procedure_header.expression;
            module_name := code_header.enclosing_load.enclosing_import.module_name;
            if !module_name && code_header.notes.count > 0
            {
                found_command := false;
                for code_header.notes if it.text == COMMAND_ANNOTATION then found_command = true;
                if found_command
                {
                    max_arguments := code_header.arguments.count;
                    min_arguments := 0;
                    found_default := false;
                    for argument, argument_index : code_header.arguments
                    {
                        is_default := argument.expression != null;
                        if is_default
                        {
                            found_default = true;
                        }
                        else
                        {
                            min_arguments += 1;
                            if found_default then compiler_report(tprint("Command procedure % has non default arguments after default ones, that doesn't fly right now.", code_header.name), make_location(code_header));
                        }
                    }

                    b : String_Builder;
                    append(*b, "__command__");
                    append(*b, code_header.name);
                    append(*b, " :: (args : []Any) -> success : bool, results : []Any, message : string\n{\n");
                    append(*b, "    if args.count ==\n");
                    append(*b, "    {\n");
                    for argument_count : min_arguments..max_arguments
                    {
                        if argument_count > min_arguments then append(*b, "\n");
                        print(*b, "        case %;\n", argument_count);
                        for argument_index : 0..argument_count-1 
                        {
                            argument := code_header.arguments[argument_index];
                            argument_type_info := ifx argument.type_inst then argument.type_inst.result else argument.expression.type;
                            argument_type_name := type_to_string(argument_type_info);
                            print(*b, "        arg_%1 := __commands_any_to_arg(args[%1], %2);\n", argument_index, argument_type_name);
                        }

                        append(*b, "        ");
                        for 0..code_header.returns.count-1
                        {
                            if it == 0 then print(*b, "result_%", it);
                                       else print(*b, ", result_%", it);
                        }
                        if code_header.returns.count > 0 then append(*b, " := ");
                        print(*b, "%(", code_header.name);
                        for argument_index : 0..argument_count-1 
                        {
                            if argument_index == 0 then print(*b, "arg_%", argument_index);
                                                   else print(*b, ", arg_%", argument_index);
                        }
                        append(*b, ");\n");
                        if code_header.returns.count > 0
                        {
                            append(*b, "        return true, array_copy(Any.[");
                            for 0..code_header.returns.count-1
                            {
                                if it == 0 then print(*b, "__commands_temporary_copy(result_%)", it);
                                           else print(*b, ", __commands_temporary_copy(result_%)", it);
                            }
                            append(*b, "],, temp), \"\";\n");
                        }
                        else append(*b, "        return true, .[], \"\";\n");
                    }

                    append(*b, "\n");
                    append(*b, "        case;\n");
                    if min_arguments == 0 && max_arguments == 0
                        print(*b, "        return false, .[], tprint(\"Invalid argument count for command %%, takes no arguments but %% were provided\", \"%1\", args.count);\n", code_header.name);
                    else if min_arguments == max_arguments
                        print(*b, "        return false, .[], tprint(\"Invalid argument count for command %%, takes %% but %% were provided\", \"%1\", %2, args.count);\n", code_header.name, min_arguments);
                    else
                        print(*b, "        return false, .[], tprint(\"Invalid argument count for command %%, takes between %% and %% but %% were provided\", \"%1\", %2, %3, args.count);\n", code_header.name, min_arguments, max_arguments);
                    append(*b, "    }\n");

                    append(*b, "}\n");

                    add_build_string(builder_to_string(*b,, temp), plugin.workspace);

                    array_add(*commands_plugin.commands_to_add, code_header);
                }
            }
        }

        case .COMPILATION_PHASE;
        phase_message := cast(*Message_Phase)message;
        if phase_message.phase == .TYPECHECKED_ALL_WE_CAN && commands_plugin.commands_to_add.count > 0
        {
            b : String_Builder;
            print(*b, "#program_export __commands__registration_round_% :: ()\n{\n", commands_plugin.round);
            defer commands_plugin.round += 1;
            for code_header : commands_plugin.commands_to_add
            {
                append(*b, "    __register_command(\"");

                // name
                append(*b, code_header.name);

                // command
                append(*b, "\", __command__");
                append(*b, code_header.name);
                append(*b, ", \"");

                // name_with_hints
                append(*b, code_header.name);
                for argument, argument_index : code_header.arguments
                {
                    is_default := argument.expression != null;
                    argument_type_info := ifx argument.type_inst then argument.type_inst.result else argument.expression.type;
                    argument_type_name := type_to_string(argument_type_info);
                    append(*b, " ");
                    if is_default then append(*b, "[");
                    append(*b, argument_type_name);
                    if is_default then append(*b, "]");
                }
                append(*b, "\"");

                append(*b, ");\n");
            }
            append(*b, "    __update_stuff_after_registering_a_bunch_of_commands();\n");
            array_reset_keeping_memory(*commands_plugin.commands_to_add);
            append(*b, "}\n");

            add_build_string(builder_to_string(*b,, temp), plugin.workspace);
        }
    }
}



initialized : u32 = 0;
init_if_needed :: ($__T : Type = void) // @@NOTE: Making this polymorphic so it doesn't try to be compiled in any case on the workspace that calls the plug-in
{
    initialize :: ()
    {
        #if OS == .WINDOWS
        {
            #import "Windows";
            handle := GetModuleHandleW(null);
            assert(handle != null);
            find_symbol :: (null_terminated_name : string) -> *void #expand { return GetProcAddress(`handle, null_terminated_name.data); }
        }
        else #if OS == .LINUX || OS == .MACOS
        {
            #import "POSIX";
            handle := dlopen(null, RTLD_LAZY);
            assert(handle != null);
            defer dlclose(handle);
            find_symbol :: (null_terminated_name : string) -> *void #expand { return dlsym(`handle, null_terminated_name.data); }
        }
        else
        {
            #assert(false);
        }

        round := 0;
        while true
        {
            defer round += 1;
            registration_procedure := cast(#type ())find_symbol(tprint("__commands__registration_round_%\0", round));
            if !registration_procedure then break;
            registration_procedure();
        }
    }
    
    #assert(OSOR_COMMANDS_PLUGIN_HAS_RUN); // @@NOTE: If this fails, you're probably importing this module but not the plug-in, you need both!

    //
    // @@NOTE: If multiple threads get past the first check, only the
    // first one that did the atomic add will do the initialization
    // while the rest just spinlock waiting for the value to show that
    // initialization has finished.
    //
    if initialized == 0xFFFFFFFF then return;
    previous := atomic_add(*initialized, 1);
    if previous == 0
    {
        defer initialized = 0xFFFFFFFF;
        initialize();
    }
    else while initialized != 0xFFFFFFFF #asm { pause; }
    #asm { mfence; }
}



parse_command_string :: (command_string : string) -> success : bool, name : string, arguments : []Any, message : string
{
    parse_assert :: (value : bool, format: string, arguments: .. Any) #expand
    {
        if !value 
        {
            `return false, "", .[], tprint(format, ..arguments);
        }
    } @PrintLike

    push_allocator(temp);

    tokenizer : Tokenizer;
    init_tokenizer(*tokenizer, command_string);

    token := tokenize_one_token(*tokenizer);
    parse_assert(token.type == .IDENTIFIER, "Couldn't find command name in '%' (first token was %(%))", command_string, token.text, token.type);
    command_name := token.text;
    command_arguments : [..]Any;

    negate_value := false;

    while true
    {
        token := tokenize_one_token(*tokenizer);
        if token.type ==
        {
            case .INTEGER;
            value : *s64 = talloc(size_of(s64)); 
            value.* = string_to_int(token.text, base = 10, T = s64);
            if negate_value 
            {
                value.* *= -1;
                negate_value = false;
            }
            array_add(*command_arguments, value.*);

            case .FLOAT;
            value : *float64 = talloc(size_of(float64)); 
            value.* = string_to_float64(token.text);
            if negate_value 
            {
                value.* *= -1;
                negate_value = false;
            }
            array_add(*command_arguments, value.*);

            case .BOOL;
            value : *bool = talloc(size_of(bool)); 
            if      compare_nocase(token.text, "true") == 0  { value.* = true;  }
            else if compare_nocase(token.text, "false") == 0 { value.* = false; }
            else parse_assert(false, "Unexpected text for a boolean value %\n", token.text); 
            array_add(*command_arguments, value.*);

            case .MINUS;
            negate_value = !negate_value;

            case .STRING; #through;
            case .IDENTIFIER;
            value : *string = talloc(size_of(string)); 
            value.* = token.text;
            array_add(*command_arguments, value.*);

            case .END;
            break;

            case;
            parse_assert(false, "Unrecognized part of command string '%' (token type = %)", token.text, token.type);
        }
    }

    return true, command_name, command_arguments, "";
}


