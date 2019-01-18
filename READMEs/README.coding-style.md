# Coding Style

By Mark Overmeer and Anton Jongsma, June 2016

## Purpose

The sole purpose for a coding style, it to get better maintainable code.
It spoils energy of the reader of code when (s)he has to work though
inconsistent layout and naming convertions.  Valuable energy which is
need to focus on the issue to be resolved.  Therefore, please try to
stick to the simple rules described here.

In case of doubt, Perl Best Practices (PBP by Damian Conway) may give you
good advice.

Taranis 3 does not always follow these rules yet, but we are working
towards it.

## Layout

- One blank line before and after each sub.
- The tabstop is 4.  Do not use blanks to adjust code.
- Each nesting adds one tab.
- No trailing blanks.
- Curly open braces '{' on the same line as their if()/while()
- Cuddled else:   '} else {'
- Avoid superfluous symbols, like parenthesis in expressions, when the
  priority of the operator is well known.

## Coding

- Each package a strict order (if applicable, separated by a blank line)
  0. copyright
  1. package statement
  2. use parent
  3. pragmas; always use strict and warnings.
  4. use external modules
  5. use Taranis modules
  6. constants
  7. @EXPORT
  8. object constructors, new/init()
  9. attribute handlers, getters/setters
  10. more subs
- Each package in a separate file
- All modules in the Taranis:: namespace
- Use real exceptions (croak) on errors
- Use Try::Tiny::try() to catch errors
- Use camelCase for methods and Packages, but lower_cased for anything else
- Subs which are not to be used outside a package start with an '\_', and
  are usually not documented in pod
- Use prototypes on functions, which adds compile-time errors (not checked
  in methods)
- Explicitly import functions from external modules, preferrably not
  via an export tag but each named separately.
- Do always cleanly import functions: no '::' when calling them.
- Do not provide global variables: use functions to get their value.
- Don't be afraid to refactor silly code.

## Documentation

There are various kinds of documentation:

0. Use American English
1. Code documention (#), to make code understandable
   * use better (variable) names to reduce the need for code comments
   * on one or more lines before the described code, indented as the code
     with a leading blank line.  Full sentences (start with a capital and
     close with a dot)
   * after a statement on the same line, with at least to blanks before
     the '#'
2. Interface documentation (pod), to describe that a function does
   * interleaved with the functions which it describes; both to lower the
     chance that it is not maintained, and as additional information to
     fulfil the interface promiss by the coder.
   * each sub which is exported (used outside the file where it is
     implemented) should have pod
   * long explenations in 'DETAILS' head1 after \_\_END\_\_
3. Usage documentation (help)
   * each script should respond to --help and -? with a short usage
     description.  It would be nice to have a manual page as well.
4. User documentation (pdf)
   * describes the interface, from the point of the user of the Taranis
     application.
5. Installation guide (pdf)
   * the installation guide should become as small as possible: as much
     work done automatically as possible

## PS:

> Programming is a Dark Art, and it will always be. The programmer is
> fighting against the two most destructive forces in the universe: entropy
> and human stupidity. They're not things you can always overcome with a
> "methodology" or on a schedule.  -- Damian Conway
