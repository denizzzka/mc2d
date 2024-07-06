module main;

import std.algorithm;
import std.conv: to;
import std.string: chomp;
import std.range;
import std.stdio;

struct CliOptions
{
    enum ShowExcluded { no, brief, full, };
    static __gshared CliOptions* _this;

    string out_file;
    bool debug_output;
    string[] include_files;
    string[] clang_opts;
    ShowExcluded show_excluded;
    uint threads = 1;
}

CliOptions options;

int main(string[] args)
{
    import std.getopt;

    {
        //TODO: add option for files splitten by zero byte
        auto helpInformation = getopt(args,
            "output", `Output file`, &options.out_file,
            "debug_output", `Add debug info to output file`, &options.debug_output,
            "include", `Additional include files`, &options.include_files,
            "clang_opts", `Clang options`, &options.clang_opts,
            "show_excluded", `<no|brief|full> Output excluded entries`, &options.show_excluded,
            "threads", `Threads number`, &options.threads,
        );

        if(options.out_file == "")
        {
            stderr.writeln("Output file not specified");
            helpInformation.helpWanted = true;
        }

        if (helpInformation.helpWanted)
        {
            defaultGetoptPrinter(`Usage: `~args[0]~" [PARAMETER]...\n"~
                `Takes a list of C files from STDIN and returns D bindings file`,
                helpInformation.options);

            return 0;
        }

        const string[] includes = options.include_files.map!(a => ["-include", a]).join.array;
        options.clang_opts ~= includes;

        options.clang_opts ~= "-ferror-limit=0";

        CliOptions._this = &options;
    }

    import std.stdio: File;

    auto outFile = File(options.out_file, "w");

    import std.parallelism;

    defaultPoolThreads(options.threads);

    const filenames = stdin.byLineCopy.array; //TODO: use asyncBuf?

    import clang_related;
    import std.parallelism;

    static auto parseF(string filename) => parseFile(filename, CliOptions._this.clang_opts);

    auto units = taskPool.amap!parseF(filenames);

    import dpp.expansion;

    auto unitsCanonicalCursors = units.map!(a => a.canonicalCursors);

    import clang;
    import storage: Key;

    unitsCanonicalCursors
        .joiner
        .tee!(a => assert(a.isFileScope))
        .each!checkAndAdd;

    static void showExcluded(in Key key, in CursorDescr c, in CliOptions.ShowExcluded opt)
    {
        stderr.writeln(">>>>>>>>>>>>>>> Key: ", key);

        static string pretty(in Cursor c) => c.getSourceRange.fileLinePrettyString~"\t"~c.toString;

        if(opt == CliOptions.ShowExcluded.brief)
        {
            stderr.writeln(pretty(c.cur));

            c.alsoExcluded.each!(a => stderr.writeln(pretty(a.cur)));
        }
        else if(opt == CliOptions.ShowExcluded.full)
            c.alsoExcluded.each!(a => stderr.writeln(a.errMsg));
    }

    import std.typecons;

    auto chunks = cStorage.getSortedDecls
        .filter!((a) {
            if(a.descr.isExcluded)
            {
                showExcluded(a.key, a.descr, options.show_excluded);
                return false;
            }
            else
                return true;
        })
        .array
        .sort!((a, b) => a.key.name < b.key.name || (a.key.name == b.key.name && a.key.kind < b.key.kind))
        .chunkBy!((a, b) => a.key.kind == b.key.kind && a.key.name == b.key.name);

    auto statements =
        chunks
        .map!(chunk => chunk.fold!(
            (ref a, ref b) => a.key.isDefinition ? a : b
        ))
        .map!(a => a.descr.cur);

    import dpp.runtime.context;
    import dpp.runtime.options: Options;

    auto dppOptions = Options();
    dppOptions.alwaysScopedEnums = true;
    dppOptions.noSystemHeaders = true;
    dppOptions.ignoreMacros = true;

    auto language = dpp.runtime.context.Language.C;
    auto context = Context(dppOptions, language);

    import dpp.runtime.app: preamble;
    outFile.writeln(preamble(true));
    outFile.writeln("import core.stdc.stdatomic;");
    outFile.writeln("alias __gnuc_va_list = va_list;");
    outFile.writeln("extern(C) {");

    static void addDContextData(ref Cursor cursor, ref Context context, string file = __FILE__, size_t line = __LINE__)
    {
        import dpp.translation.translation;

        const indentation = context.indentation;
        const lines = translateTopLevelCursor(cursor, context, file, line);
        context.writeln(lines);
        context.setIndentation(indentation);
    }

    statements
        .each!((a){
                if(options.debug_output) context.writeln("\n\n// Cursor: " ~ a.to!string);
                addDContextData(a, context);
            });

    context.fixNames;

    outFile.writeln(context.translation);

    outFile.writeln("}");

    return 0;
}
