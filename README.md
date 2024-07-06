mc2d - tool for merging C files into D bindings
=====

#### Build
As usual for D software:

```
$ git clone https://github.com/denizzzka/mc2d.git
$ cd mc2d
$ dub build
```


#### How to use?

* Remark

It is need to understand that correct D bindings can only be obtained
if all the necessary C compiler options and DEFINEs known, including individual
defines for subprojects/submodules/libraries/components/etc if we are talking about a complex system.
Usually, searching for correct defines is the most difficult part of creating a binding.

For this tool I propose to shift all this work to the C compiler.

* Thus, the first step when creating a binding is to obtain the preprocessed sources (usually files with a rare *.i extension)

To get these files only need to add `-save-temps` compiler option during compilation of C code to which bindings needed to obtain.
Build systems usually providing way to add custom options so it's not a problem.

* The next step is to create a list of `*.i` files - mc2d accepts such lists as input

In the simplest case, this is a recursive search with `find`:

```
$ find <path_to_preprocessed_files_dir> -type f -name "*.i" > files_list.txt
```

* Now you can run mc2d:

```
$ ./mc2d --clang_opts="--target=riscv32" --threads=8 \
    --output binding_module.d < files_list.txt
```

Note that it is still need to specify target architecture because C variables sizes depend on it.

Great, now if everything went well you will obtain `binding_module.d` module!

* Caveat

This tool excludes from resulting binding global C statements that have the same names but different value or body.
Unfortunately, during the merge process it is impossible to determine whether such matching statements belong to different object files.

Practice has shown that this is not a serious problem in real code.

If you need to access the excluded statement try to exclude from input all other files containing same statement (use `--show_excluded` to find these files)
