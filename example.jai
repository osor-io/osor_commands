


//
// @@NOTE: At the time of writing it's somewhat annoying to provide the import directory
// for external plugins so it gets picked up by the metaprogram and it can use them.
//
// To build this example you'd need to make sure to provide the import dir to give access to
// the needed modules both for the workspace of this program but also to the metaprogram that's
// going to import and call the module.
//
// The line I'm using locally is as follows (replace X:\jai_modules with your own include path):
//
//     jai example.jai -import_dir X:\jai_modules -plug osor_commands -- import_dir X:\jai_modules
//
// The key parts being:
//   
//     -import_dir X:\jai_modules     -> This adds the import directory for the workspace of this program (example.jai)
//     -plug osor_commands            -> This tells the metaprogram to go search for our plugin and allow it to hook into the metaprogram's message loop 
//     -- import_dir X:\jai_modules   -> Any options after "--" are passed to the compiler, the import_dir at this level will make our module available to the metaprogram so it can load it as a plugin
//
// To use this module in a more involved project with it's own metaprogram you can initialize the
// metaprogram workspace with the required import directories. But for the purposes of keeping
// the example in a single file and not require a full metaprogram, I'm going with this here.
//
//                                                   - Ruben Osorio, 21/07/2024
//



#import "Basic";
#import "osor_commands";



main :: ()
{
    simple();
    errors();
    return_values();
    supported_types();
    default_values();
    console();
}



simple :: ()
{
    print_example_name("Simple Example");

    //
    // The basic usage is as follows. Somewhere in our program we have
    // annotated a procedure with @Command. Then later we can call
    // execute_command(...) with a single string that represents our
    // call to that command.
    //
    // We specify the command name and pass in parameters by putting
    // them in order on the string, separated by any whitespace, as
    // follows:  
    //
    execute_command("my_simple_command 123");
}
my_simple_command :: (a : int)
{
    print("A was %\n", a);
} @Command



errors :: ()
{
    print_example_name("Handling Errors");

    //
    // Of course, there could be a mistake in the command string to execute, 
    // such as incorrect types to a command, passing integers that don't fit
    // in the parameter, looking for a command that doesn't exist, etc.
    //
    // By checking the success of the operation and showing the message, you
    // should get an idea of what has gone wrong.
    //
    // In this case we're going to pass an integer instead of the string
    // that the oopsies command takes.
    //
    success, results, message := execute_command("oopsies 123");
    if !success
    {
        print("Oh no! We tried to run oopsies but we called it incorrectly, the error is:\n%\n", message);
    }
}
oopsies :: (s : string)
{
    print("The string is %\n", s);
} @Command



return_values :: ()
{
    print_example_name("Getting Return Values");

    //
    // The commands are allowed to return values too, but since we need to go
    // through the shared interface of execute_command(...), they return everything
    // in an array of Any ([]Any).
    //
    // Here we'll take those and print what the command returned.
    //
    success, results := execute_command("returns_something 123 123.123");
    assert(success);

    print("Our command returned:\n");
    for results print("  % - %\n", it_index, it);
}
returns_something :: (a : int, b : float) -> float, string
{
    return cast(float)a + b, tprint("Here you go, % and % added together", a, b);
} @Command



supported_types :: ()
{
    print_example_name("Checking all supported types");

    //
    // Seeing the supported basic types, as well as enums which are just
    // matched by name with the provided identifier
    //
    execute_command("all_dem_types 123 456.789 true pepe MANGO 42");

    //
    // To pass in strings, you can also use double quotes if you want
    // to use spaces in the middle
    //
    execute_command(#string DONE
    all_dem_types 123 456.789 false "my string with a bunch of spaces, this could be anything" BANANA 42
    DONE);
}
My_Enum :: enum
{
    BANANA;
    MANGO;
}
all_dem_types :: (a : u8, b : float64, c : bool, d : string, e : My_Enum, f : *int)
{
    print("We got %,%,%,%,%,%\n", a, b, c, d, e, f.*);
} @Command



default_values :: ()
{
    print_example_name("Default Values");

    //
    // Here we're calling the same command either by passing a parameter
    // or by letting it default to whatever the command specified in the
    // function signature.
    //
    execute_command("with_default_values 123");
    execute_command("with_default_values");

    //
    // The combination of pointers and default arguments is useful for
    // commands like this. In this case we can take in a bool or nothing at
    // all. If we take nothing, we toggle a global bool, but if a value
    // is passed, we set it to the given value.
    //
    execute_command("toggle_my_bool");
    execute_command("toggle_my_bool true");
    execute_command("toggle_my_bool false");
    execute_command("toggle_my_bool");
}
with_default_values :: (a : int = 99999999)
{
    print("A was %\n", a);
} @Command
my_bool := true;
toggle_my_bool :: (v : *bool = null)
{
    if v
    {
        my_bool = v.*;
        print("We got a parameter, setting my_bool to %\n", my_bool);
    }
    else
    {
        my_bool = !my_bool;
        print("We didn't get a parameter, toggling my_bool to %\n", my_bool);
    }
} @Command



console :: ()
{
    print_example_name("Console");

    //
    // And of course a major use-case of a system like this would be to take user input and call any of
    // the commands available. Here we take user input and let them call any of the @Commands in this program.
    //
    // First we show all the commands with the parameters they take. This also shows
    // which commands are optional by surrounding them with square brackets, as in
    //
    //     with_default_values [int]
    //

    print("Available commands with argument hints:\n");
    all_commands := get_all_commands();
    for all_commands
    {
        print("    %\n", it.name_with_hints);
    }

    success, results, message := execute_command(read_input("Call any of the commands above and press enter:\n"));
    if !success
    {
        print("Error calling command:\n%\n", message);
    }
    else
    {
        for results print("  % - %\n", it_index, it);
    }
}



#scope_file



print_example_name :: (name : string) #expand
{
    for 0..(8 + name.count)-1 print("#");
    print("\n### % ###\n", name);
    for 0..(8 + name.count)-1 print("#");
    print("\n");
    `defer print("\n\n\n");
}



//
// Making one of these cause at the time of writing there's no standard way to read from
// standard input. This does the job for this example though.
//
read_input :: (prompt := "") -> string
{
    write_string(prompt);

    buffer : []u8;
    buffer.count = 128;
    buffer.data = talloc(buffer.count);
    #if OS == .WINDOWS
    {
        #import "Windows";
        bytes_read : u32;
        success := ReadFile(GetStdHandle(STD_INPUT_HANDLE), buffer.data, xx buffer.count, *bytes_read, null);
        assert(success == .TRUE);
    }
    else #if OS == .LINUX || OS == .MACOS
    {
        #import "POSIX";
        bytes_read := read(STDIN_FILENO, buffer.data, xx buffer.count);
        assert(bytes_read >= 0);
    }
    if bytes_read
    {
        result : string;
        result.data  = buffer.data;
        result.count = bytes_read;
        if result[result.count-1] == #char "\n" result.count -= 1;
        if result[result.count-1] == #char "\r" result.count -= 1;
        return result;
    }
    return "";
}




