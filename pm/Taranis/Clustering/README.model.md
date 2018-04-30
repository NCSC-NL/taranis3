==== Language Models

== History

This information has been removed from the administration manual 3.3,
because its implementation was not complete.  The only way to add new
languages is currently by modifying the Taranis code.  As the core
developers to help you when you need it.

== Status

Taranis currently supports clustering for two languages: Dutch and
English.  Their access is hardcoded.

Which clustering configuration will be used for a specific item, depends
on the language that you assign to a source. Clustering will only be
performed if the language you specified with your source also has an
according clustering definition.

== Adding language tables

If you want to add a new language for clustering you must create a new
language file as defined in “BG-model”. Such a file contains all
keywords found in a sample selection of publications in that language
along with some additional information.

Below is an example of such a definition taken from the BGEN.model
(English) included in your Taranis installation:

``16 that 147724 434955``

You must interpret this line as follows: on place 16 of the most common
words in this language is the word “that” that was found in 147.724
documents (document frequency or df) and was used 4.345.955 times (term
frequency or tf) in those documents.

If you want to generate a language file you must thus have a
representative selection of documents from this language, find the
keywords used and count those keywords in terms of df and tf. The larger
the set of documents is, the better clustering will work.
