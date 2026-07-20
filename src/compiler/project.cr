// === project.cr ===
// Project-level operations: reads Core.toml, resolves source files,
// provides memory layout to the backend.
// Depends on toml.cr for low-level key-value parsing.

// Set by load_project() — used by read_project_dir in main.cr
g_project_source_dir : string, mut;

// Load project config. Returns main_source, sets g_project_source_dir as side effect.
fn load_project(dir: string) -> string {
    sd : ., mut = "";
    toml_path : ., mut = dir;
    if str_eq(get_char(dir, str_len(dir) - 1), "/") != 0 {
        sd = dir;
        toml_path = dir + "Core.toml";
    } else {
        sd = dir + "/";
        toml_path = dir + "/Core.toml";
    }

    tc := read_file(toml_path);
    pname : ., mut = "";
    if str_len(tc) > 0 {
        pname = extract_toml_name(tc);
    }

    main_path : ., mut = sd + "main.cr";
    source := read_file(main_path);
    if str_len(source) == 0 {
        main_path = "main.cr";
        source = read_file(main_path);
    }

    g_project_source_dir = sd;
    if str_len(pname) > 0 {
        print("  project: ");
        println(pname);
    }
    if str_len(source) > 0 {
        print("  main.cr: ");
        println(main_path);
    }

    return source;
}
