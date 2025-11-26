import std.stdio;
import std.conv;
import std.algorithm.sorting : sort;
import std.algorithm.mutation : reverse;

enum TypeKind {Atomic, Struct, Union}

struct TypeSum
{   
    TypeKind kind;
    string name;
    int size = 0;
    int alignment = 0;
    int heuristic_wasted = 0; // Exclusivo para caso de Struct
    string[] types = []; // Es vacío exclusivamente cuando se trata de un tipo atómico 
}

struct PlacedType {
    string name;
    TypeSum ts;
    size_t offset;
}

struct Hole {
    size_t start;
    size_t end;   // Exclusivo
}

size_t alignTo(size_t x, size_t a)
{
    // Alineación genérica
    return ((x + a - 1) / a) * a;
}

bool is_type_list_valid(string[] type_list, TypeSum[string] types){
    foreach (x; type_list){
        if(!(x in types)){
            return false;
        }
    }
    return true;
}

TypeSum[string] create_atomic_type(string name, int size, int alignment, TypeSum[string] types){
    if(!(name in types)){
        TypeSum new_type;
        new_type.kind = TypeKind.Atomic;
        new_type.name = name;
        new_type.size = size;
        new_type.alignment = alignment;
        types[name] = new_type;
    } else {
        writeln("El tipo ", name, " ya existe.");
    }
    return types;
}

TypeSum[string] create_struct_type(string name, string[] struct_types, TypeSum[string] types){
    if(name in types){
        writeln("El tipo ", name, " ya existe.");
        return types;
    }

    if(!is_type_list_valid(struct_types, types)){
        writeln("Algún tipo definido para el struct no existe.");
        return types;
    }

    TypeSum new_type;
    new_type.kind = TypeKind.Struct;
    new_type.name = name;
    new_type.types = struct_types;

    int[] result = best_fit_heuristic_for_layout(struct_types, types);

    new_type.size = result[1];
    new_type.heuristic_wasted = result[0];

    new_type.alignment = result[2];

    types[name] = new_type;
    return types;
}

TypeSum[string] create_union_type(string name, string[] union_types, TypeSum[string] types){
    if(name in types){
        writeln("El tipo ", name, " ya existe.");
        return types;
    }

    if(!is_type_list_valid(union_types, types)){
        writeln("Algún tipo definido para la union no existe.");
        return types;
    }

    TypeSum new_type;
    new_type.kind = TypeKind.Union;
    new_type.name = name;
    new_type.types = union_types;

    // Calcular el tamaño de el tipo suma, en este caso, debe ser el tamaño del tipo que tiene mayor tamaño
    int max_size = 0;
    foreach(type; union_types){
        if(types[type].kind == TypeKind.Atomic && types[type].size > max_size){
            max_size = types[type].size;
        }
    }

    new_type.size = max_size;

    // Calcular la alineación, constará del mínimo común múltiplo entre las alineaciones de los tipos internos
    int union_lcm = types[union_types[0]].alignment;
    foreach(type; union_types[1..$]){
        union_lcm = (union_lcm / gcd(union_lcm, types[type].alignment)) * types[type].alignment;
    }

    new_type.alignment = union_lcm;
    types[name] = new_type;
    
    return types;
}

int gcd(int x, int y){
    while(x != y){
        if(x >= y){
            x = x - y;
        } else{
            y = y - x;
        }
    }
    return x;
}

int[] not_packed_method_for_layout(string[] types, TypeSum[string] global_types){
    TypeSum[] ordered;
    foreach(name; types) ordered ~= global_types[name];

    Hole[] holes;
    size_t struct_size = 0;

    PlacedType[] result;
    foreach(ts; ordered){
        
        size_t aligned = alignTo(struct_size, ts.alignment);

        result ~= PlacedType(ts.name, ts, aligned);

        if (aligned > struct_size)
            holes ~= Hole(struct_size, aligned);

        struct_size = aligned + ts.size;
    }

    size_t total_size = struct_size;
    size_t wasted_bytes = 0;
    foreach (h; holes)
        wasted_bytes += (h.end - h.start);
    
    return [to!int(wasted_bytes), to!int(total_size)];

}  

void get_type_description(string name, TypeSum[string] types){
    if(!(name in types)){
        writeln("El tipo ", name, " no existe.");
        return;
    }

    switch (types[name].kind){
        case TypeKind.Atomic:
            writeln("El objeto ", name, " es de tipo atómico.");
            writeln("Tiene las siguientes características:");
            writeln("Tamaño: ", types[name].size, " Bytes");
            writeln("Alineación: ", types[name].alignment);
            writeln("Cantidad de bytes desperdiciados en cualquier representación: 0B");
            break;
        case TypeKind.Union:
            writeln("El objeto '", name, "' es de tipo union.");
            writeln("Contenido: ");
            writeln("----------------------------------------");
            foreach(type; types[name].types){
                writeln("    ", types[type].name, " | ", types[type].size, " Bytes | ", types[type].alignment, " de alineación.");
            }
            writeln("----------------------------------------");
            writeln("Tamaño: ", types[name].size, " Bytes");
            writeln("Alineación: ", types[name].alignment);
            writeln("Cantidad de bytes desperdiciados: Depende del tipo a tiempo de ejecución");
            foreach(type; types[name].types){
                writeln("    Si es ", types[type].name, ", entonces ", types[name].size - types[type].size, " Bytes.");
            }
            break;
        case TypeKind.Struct:
            writeln("El objeto '", name, "' es de tipo struct.");
            writeln("Contenido: ");
            writeln("----------------------------------------");
            int total_size;
            foreach(type; types[name].types){
                writeln("    ", types[type].name, " | ", types[type].size, " Bytes | ", types[type].alignment, " de alineación.");
                total_size += types[type].size;
            }
            writeln("----------------------------------------");
            writeln("Tamaño y desperdicio");

            int[] not_packet_result = not_packed_method_for_layout(types[name].types, types);

            writeln("    No empaquetado: ", not_packet_result[1], " Bytes y ", not_packet_result[0], " Bytes de desperdicio.");
            writeln("    Empaquetado: ", total_size, " Bytes y 0 Bytes de desperdicio.");
            writeln("    Heurística: ", types[name].size, " Bytes y ", types[name].heuristic_wasted, " Bytes desperdiciados.");
            break;


        default:
            break;
    }

}         


int[] best_fit_heuristic_for_layout(string[] types, TypeSum[string] global_types)
{
    // 1) ordenar tipos
    TypeSum[] ordered;
    foreach(name; types) ordered ~= global_types[name];

    ordered.sort!((a, b) =>
        (a.alignment > b.alignment) ||
        (a.alignment == b.alignment && a.size > b.size)
    );

    Hole[] holes;
    size_t struct_size = 0;

    PlacedType[] result;

    foreach(ts; ordered)
    {
        size_t best_hole_index = -1;
        size_t best_fit_padding = size_t.max;
        size_t best_aligned_offset;

        // Intentar colocarlo en cada hueco
        foreach(i, h; holes)
        {
            size_t aligned = alignTo(h.start, ts.alignment);
            size_t diff = h.end - aligned;

            if (diff >= ts.size)
            {
                size_t leftover = diff - ts.size;

                if (leftover < best_fit_padding) {
                    best_fit_padding = leftover;
                    best_hole_index = i;
                    best_aligned_offset = aligned;
                }
            }
        }

        if (best_hole_index != -1)
        {
            result ~= PlacedType(ts.name, ts, best_aligned_offset);

            Hole h = holes[best_hole_index];

            // Partir hueco según donde cayó
            Hole[] new_holes;

            if (best_aligned_offset > h.start)
                new_holes ~= Hole(h.start, best_aligned_offset);

            if (best_aligned_offset + ts.size < h.end)
                new_holes ~= Hole(best_aligned_offset + ts.size, h.end);

            holes[best_hole_index .. best_hole_index+1] = new_holes;
        }
        else
        {
            // Colocar al final
            size_t aligned = alignTo(struct_size, ts.alignment);

            result ~= PlacedType(ts.name, ts, aligned);

            if (aligned > struct_size)
                holes ~= Hole(struct_size, aligned);

            struct_size = aligned + ts.size;
        }
    }

    size_t total_size = struct_size;
    size_t wasted_bytes = 0;
    foreach (h; holes)
        wasted_bytes += (h.end - h.start);
    
    return [to!int(wasted_bytes), to!int(total_size), ordered[0].alignment];
}


void proccess_command(string command){}

void main(){

    TypeSum[string] types;
    types = create_atomic_type("char", 3, 4, types);
    types = create_atomic_type("int", 2, 3, types);
    types = create_union_type("animal", ["int", "char"], types);
    types = create_struct_type("vector", ["int", "char", "animal"], types);

    get_type_description("animal", types);
    get_type_description("vector", types);

}