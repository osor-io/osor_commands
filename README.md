# :pager: A command module for Jai 

A simple command module for the Jai programming language. You can check the code in [module.jai](parse.jai) and a few examples of how to use them in [example.jai](example.jai).

This is making the local commands and console code I had into a plugin + module setup so it can be shared around. That code itself originally comes from the ideas presented by Jonathan Blow in [his console commands video](https://www.youtube.com/watch?v=N2UdveBwWY4).

## How To

The idea is to allow you to annotate procedures in your codebase with `@Command` (or an annotation of your choice) and be able to call them at runtime with an input string via `execute_command(...)`. This is very useful to expose code to a user-facing console, allow some simple scripting, etc. 

As an example, you would create a command as follows:
```
my_command :: (v : int)
{ 
    /* . . . */
} @Command

```
Then call it somewhere in your code by doing:
```
execute_command("my_command 123");
```
Or most likely, taking some other input and passing it through:
```
user_input := get_user_input();
execute_command(user_input);
```
A favorite of mine is to do a command to toggle or set a value to enable a system or some debug code:
```
should_my_code_run := false;
toggle_my_code :: (v : *bool = null)
{
    if v then should_my_code_run = v.*;
         else should_my_code_run = !should_my_code_run;
} @Command
```
And hook this up to a user-facing developer console, so you could do `toggle_my_code` to just keep switching something on or off, or do `toggle_my_code true/false` to set it explicitly to something. A similar idea would work to set a global setting to some specific value, or reset it to the default value if no parameter is provided. 

Better examples about the capabilities of this are in [example.jai](example.jai). Stuff such as errors in the command string, handling return values, show all the supported types and their syntax, default values, pointers, etc.

## Use Plugin

The module uses Jai's plug-in system to get access to the metaprogram messages and find all the tagged command procedures. This means that you need to either add it to your metaprogram's plug-ins in code or pass in `jai ... -plug osor_commands` when compiling.

Besides adding the plug-in, you still need to `#import "osor_commands"` in your program since that provides the implementation of `execute_command` and the rest of the exposed functionality. 

## License

I want people to be able to just use this without thinking about licensing, although give me a shout if you do use it and attribution is appreciated 😊. Replicating STB's (https://github.com/nothings/stb) licensing stuff where you can choose to use public domain or MIT.
