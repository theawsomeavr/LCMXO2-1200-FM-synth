static import std.process;
static import std.stdio;
static import std.file;
static import std.path;
static import std.format;
static import std.math;
import std.string : StringException;

alias Fmt = std.format.format;

const string TARGET = "flaya";
const string MAIN_ENTRY = "flaya.d";
const string DIAMOND_PATH = "/home/Goyco/khStuff/coding_stuff/sdks/lattice_diamond/";
const string BUILD_DIR = "build/";
const string TMP_DIR = BUILD_DIR ~ "tmp/";

enum CompileRes {
    Ok,
    NoChange,
    Failed,
};

CompileRes recompile_program(){
    const(char[])[] args = [ "gdc", "-O0", "-g", "-o", TARGET ~ ".new", MAIN_ENTRY ];

    bool should_recompile = 0;

    auto binary_date = std.file.timeLastModified(TARGET);
    auto source_date = std.file.timeLastModified(MAIN_ENTRY);

    if(source_date > binary_date){
        should_recompile = 1;
    }
    if(!should_recompile)return CompileRes.NoChange;

    std.stdio.writeln("Source changed, recompiling");

    std.stdio.writeln("CMD: ", args);
    bool success = std.process.wait(std.process.spawnProcess(args)) == 0;
    if(success){
        std.file.rename(TARGET ~ ".new", TARGET);
        return CompileRes.Ok;
    }

    return CompileRes.Failed;
}

struct Optional(T) {
    /// the value (if present)
    private T value;

    /// whether `value` is set
    private bool present;

  nothrow:

    /// Creates an `Optional` with the given value
    this(T value)
    {
        this.value = value;
        this.present = true;
    }

    /// Returns: Whether this `Optional` contains a value
    bool isPresent() const { return this.present; }

    /// Returns: Whether this `Optional` does not contain a value
    bool isEmpty() const { return !this.present; }
    /// Returns: The value if present
    inout(T) get() inout { assert(present); return value; }

    /// Returns: Whether this `Optional` contains the supplied value
    bool hasValue(const T exp) const { return present && value == exp; }
}

struct FpgaInfo {
    string family;
    string model;
    string packaging;
    string speed;
};

enum Source {
    Verilog,
    Mapping,
    VHDL,
};

struct Diamond {
    static string[string] tools_env;
    static const string foundry = DIAMOND_PATH ~ "ispfpga/";
    static const string foundry_bin = foundry ~ "bin/lin64/";

    struct Srcs {
        string[] verilog, mapping, vhdl;
        string[] includes;
    };
    static string top_class;
    static Srcs src_lists;
    static Source[] src_types;
    static FpgaInfo fpga_info;
    static string project_name;

    static void create(string project_name){
        if(!std.file.exists(BUILD_DIR)){
            std.file.mkdir(BUILD_DIR);
        }
        if(!std.file.exists(TMP_DIR)){
            std.file.mkdir(TMP_DIR);
        }

        std.stdio.writeln("Preparing environment variables");
        Diamond.tools_env["TEMP"] = "/tmp";
        Diamond.tools_env["LSC_INI_PATH"] = "";
        Diamond.tools_env["LSC_DIAMOND"] = "true";
        Diamond.tools_env["TCL_LIBRARY"] = DIAMOND_PATH ~ "tcltk/lib/tcl8.5";
        Diamond.tools_env["FOUNDRY"] = Diamond.foundry;

        auto new_path = Diamond.foundry_bin ~ ":" ~ std.process.environment.get("PATH");
        Diamond.tools_env["PATH"] = new_path;
        Diamond.tools_env["LD_LIBRARY_PATH"] = Diamond.foundry_bin;
        Diamond.project_name = project_name;
    }

    static void set_source_type(Source[] types){
        Diamond.src_types = types;
    }

    static void set_fpga(FpgaInfo info){
        Diamond.fpga_info = info;
    }

    static void src_dir(string path, int depth = -1){
        if(depth == 0)return;

        bool had_files = 0;

        if(!std.file.exists(path) || !std.file.isDir(path)){
            throw new StringException(Fmt("Src directory is not a valid path %s", path));
        }

        auto dir_iter = std.file.dirEntries(path, std.file.SpanMode.shallow);

        foreach(ref file; dir_iter){
            if(file.isDir){
                Diamond.src_dir(file, depth-1);
                continue;
            }
            if(!file.isFile)continue;
            string ext = std.path.extension(file.name);
            Optional!Source file_type;
            foreach(type; Diamond.src_types){
                string type_ext;
                final switch(type){
                    case Source.VHDL:    type_ext = ".vhd"; break;
                    case Source.Verilog: type_ext = ".v"; break;
                    case Source.Mapping: type_ext = ".lpf"; break;
                }

                if(ext == type_ext){
                    file_type = Optional!Source(type);
                    break;
                }
            }
            if(file_type.isEmpty())continue;

            final switch(file_type.get()){
                case Source.VHDL:
                    Diamond.src_lists.vhdl ~= file.name;
                    break;
                case Source.Verilog:
                    Diamond.src_lists.verilog ~= file.name;
                    break;
                case Source.Mapping:
                    Diamond.src_lists.mapping ~= file.name;
                    break;
            }
            std.stdio.writefln("Adding file: %s", file.name);
            had_files = 1;
        }

        if(had_files){
            Diamond.src_lists.includes ~= path;
        }
    }

    static void set_top_class(string top_class){
        Diamond.top_class = top_class;
    }

    static void synthesise(){
        const(char[])[] args = [ Diamond.foundry_bin ~ "synthesis",
            "-a", Diamond.fpga_info.family,
            "-d", Diamond.fpga_info.model,
            "-t", Diamond.fpga_info.packaging,
            "-s", Diamond.fpga_info.speed,

            "-top", Diamond.top_class,
        ];

        if(Diamond.src_lists.vhdl.length){
            args ~= "-vhd";
            foreach(ref file; Diamond.src_lists.vhdl){
                args ~= std.path.absolutePath(file);
            }
        }

        if(Diamond.src_lists.verilog.length){
            args ~= "-ver";
            foreach(ref file; Diamond.src_lists.verilog){
                args ~= std.path.absolutePath(file);
            }
        }

        // -p is similar to -I for gcc
        args ~= [ "-p",
             foundry ~ "xo2c00/data",
        ];
        foreach(ref file; Diamond.src_lists.includes){
            args ~= std.path.absolutePath(file);
        }

        args ~= [ "-ngd", std.path.absolutePath(BUILD_DIR ~ Diamond.project_name ~ ".ngd") ];

        std.stdio.writeln("CMD: ", args);
        auto cmd = std.process.spawnProcess(args, Diamond.tools_env, workDir: TMP_DIR);
        if(std.process.wait(cmd) != 0){
            throw new StringException("Failed to synthesise code");
        }

    }

    static void mapping(){
        const(char[])[] args = [ Diamond.foundry_bin ~ "map",
            "-a", Diamond.fpga_info.family,
            "-p", Diamond.fpga_info.model,
            "-t", Diamond.fpga_info.packaging,
            "-s", Diamond.fpga_info.speed,
            "-oc", "Commercial", std.path.absolutePath(BUILD_DIR ~ Diamond.project_name ~ ".ngd"),
            "-o", std.path.absolutePath(BUILD_DIR ~ Diamond.project_name ~ "_map.ncd"),
            "-pr", std.path.absolutePath(BUILD_DIR ~ Diamond.project_name ~ "_map.prf"),
            "-c", "0",
        ];

        if(Diamond.src_lists.mapping.length){
            args ~= "-lpf";
            foreach(ref file; Diamond.src_lists.mapping){
                args ~= std.path.absolutePath(file);
            }
        }

        std.stdio.writeln("CMD: ", args);
        auto cmd = std.process.spawnProcess(args, Diamond.tools_env, workDir: TMP_DIR);
        if(std.process.wait(cmd) != 0){
            throw new StringException("Failed to map code");
        }
    }

    static void par(){
        auto base = std.path.absolutePath(BUILD_DIR ~ Diamond.project_name);
        auto args = [ Diamond.foundry_bin ~ "par", "-w", base ~ "_map.ncd", base ~ ".ncd" ];

        std.stdio.writeln("CMD: ", args);
        auto cmd = std.process.spawnProcess(args, Diamond.tools_env, workDir: TMP_DIR);
        if(std.process.wait(cmd) != 0){
            throw new StringException("Failed to par code");
        }
    }

    static void bitgen(){
        auto base = std.path.absolutePath(BUILD_DIR ~ Diamond.project_name);
        auto output_bit = std.path.absolutePath(Diamond.project_name ~ ".bit");
        auto args = [ Diamond.foundry_bin ~ "bitgen", "-w",
             base ~ ".ncd",
             output_bit,
             base ~ "_map.prf"
        ];

        std.stdio.writeln("CMD: ", args);
        auto cmd = std.process.spawnProcess(args, Diamond.tools_env, workDir: TMP_DIR);
        if(std.process.wait(cmd) != 0){
            throw new StringException("Failed to generate bit stream");
        }
    }

    static void flash(){
        auto output_bit = std.path.absolutePath(Diamond.project_name ~ ".bit");
        auto args = [
            "openFPGALoader", "--verbose", "-c", "dirtyJtag", output_bit
        ];

        std.stdio.writeln("CMD: ", args);
        auto cmd = std.process.spawnProcess(args);
        if(std.process.wait(cmd) != 0){
            throw new StringException("Failed to flash fpga");
        }
    }
};

void generate_sine_table(){
    auto sine_table = std.stdio.File("tables.v", "w+");
    const double offset = std.math.PI / 4. / 256.;
    double MAX_VALUE = std.math.log(std.math.sin(offset)) / 1023.;
    double INV_MAX_VALUE = 1. / MAX_VALUE;

    foreach(i; 0 .. 0x100){
        double t = i / cast(float)0x400 * 2 * std.math.PI;
        double value = std.math.log(std.math.sin(t + offset)) * INV_MAX_VALUE;
        int v = cast(int)(value);

        bool insert_newline = (i & 0xf) == 0xf;

        sine_table.writef("sine_log_table[8'h%03x] = 10'h%03x;", i, v);
        if(insert_newline){
            sine_table.write("\n");
        } else {
            sine_table.write(" ");
        }
    }

    foreach(i; 0 .. 0x600){
        double value = 511*std.math.exp(i * MAX_VALUE);
        int v = cast(int)(value);

        bool insert_newline = (i & 0xf) == 0xf;

        sine_table.writef("exp_table[11'h%03x] = 10'h%03x;", i, v);
        if(insert_newline){
            sine_table.write("\n");
        } else {
            sine_table.write(" ");
        }
    }
    sine_table.close();
}

void generate_freq_table(){
    auto sine_table = std.stdio.File("freq_tables.v", "w+");

    foreach(i; 0 .. 0x7f){
        double freq = 440 * std.math.pow(2, (i - 69) / 12.0);
        int v = cast(int)(freq * (1<<20) / 31250.0);

        bool insert_newline = (i & 0xf) == 0xf;

        sine_table.writef("freq[7'h%02x] = %d;", i, v);
        if(insert_newline){
            sine_table.write("\n");
        } else {
            sine_table.write(" ");
        }
    }
    sine_table.close();
}

int main() {
    final switch(recompile_program()){
        case CompileRes.Ok:
            return std.process.wait(std.process.spawnProcess(["./" ~ TARGET]));
        case CompileRes.Failed:
            return -1;
        case CompileRes.NoChange: break;
    }

    // generate_sine_table();
    // return 0;

    try {
        Diamond.create("main");
        Diamond.set_source_type([ Source.Verilog, Source.Mapping ]);

        // TinyFPGA config
        Diamond.set_fpga(FpgaInfo(
            family:    "MachXO2",
            model:     "LCMXO2-1200HC",
            packaging: "QFN32",
            speed:     "6"
        ));

        Diamond.src_dir("./test_src");
        Diamond.set_top_class("Mapping");

        Diamond.synthesise();
        Diamond.mapping();
        Diamond.par();
        Diamond.bitgen();
        Diamond.flash();

    } catch(StringException err){
        std.stdio.writefln("Error occurred:\n%s", err.toString());
        return -1;
    }
    return 0;
}
