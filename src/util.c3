module simple_player::util;

import std::io, std::time;

macro @display($Type, x, String end = "\n", String $start = "") {
    $switch $Type::kind:
        $case VOID:
            io::print("(void)");
        $case BOOL:
            io::printf("(bool)%s", x);
        $case SIGNED_INT:
        $case UNSIGNED_INT:
        $case FLOAT:
        $case SLICE:
            io::printf("(%s)%s", $Type::name, x);
        $case ENUM:
            io::printf("(enum)%s", x);
        $case ARRAY:
            io::printf("(array)%s", x);
        $case STRUCT:
            io::printfn("(struct)%s {", $Type::name);
            $foreach $i, $x : $Type::members:
                io::printf("%s%s: ", $start +++ "    ", $x.name);
                $if $i + 1 < $Type::members.len:
                    @display($x.type, x.$eval($x.name), ",\n", $start +++ "    ");
                $else
                    @display($x.type, x.$eval($x.name), "\n", $start +++ "    ");
                $endif
            $endforeach
            io::printf("%s}", $start);
        $case FUNC:
            io::printf("(fn %s(", $Type::returns.name);
            $foreach $i, $x : $Type::params:
                io::printf("%s %s", $x.type.name, $x.name);
                $if $i + 1 < $Type::params.len:
                    io::print(", ");
                $endif
            $endforeach
            io::printf(")) @ %p", x);
        $case POINTER:
            io::printf("(%s) @ %p -> ", $Type::name, x);
            $if $Type::inner.kind == VOID:
                io::print("void*");
            $else
                if (x == null) {
                    io::print("NULL");
                } else {
                    @display($Type::inner, *x, "", $start);
                }
            $endif
        $case TYPEDEF:
            $if types::is_same($Type, String):
                io::printf(`(String)"%s"`, x);
            $else
                io::printf("(%s)", $Type::name);
            $endif
    $endswitch
    io::printf("%s", end);
}

fn Duration Time.elapsed(self) => time::now() - self;
