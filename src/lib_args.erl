%%----------------------------------------------------
%% @doc
%% 命令行escript参数解析库
%% @author Eric Wong
%% @end
%% Created : 2021-11-12 14:26 Friday
%%----------------------------------------------------
-module(lib_args).
-export([
        parse/2
        ,usage/2
        ,cfg/1
    ]).

-define(EXIT_SUCCESS, 0).
-define(EXIT_FALIURE, 1).
-type exit_code() :: ?EXIT_SUCCESS | ?EXIT_FALIURE.

%% 参数配置 short/long 至少一个有效
-record(arg, {
        %% 描述内容 bitstring
        desc = <<"display this help and exit">>
        %% 是否必填项
        ,required = false
        %% -h 短命令 一个字符 可为 undefined
        ,short = undefined
        %% --help 长命令 可为 undefined
        ,long = undefined
        %% 参数个数(参数名称列表) 空格分割
        ,arg_name = []
    }).

%% 脚本配置
-record(cfg, {
        %% 脚本描述
        desc = <<"default escript desc cfg">>
        %% 脚本参数组
        ,args = []
        %% 脚本实例 可选
        ,example = undefined
        %% 脚本目标参数
        ,target = undefined
        %% 脚本目标参数可选
        ,required = false
        %% 脚本系统参数组
        ,sys = []
    }).

%%----------------------------------------------------
%% 外部接口
%%----------------------------------------------------
-spec parse([string()], #cfg{}) -> [{Short::string(), Long::string(), [term()]}].
parse(Args, Cfg) ->
    do_parse(Args, Cfg).

%% @doc 调用此函数将会打印脚本使用方式信息并以exit_code()退出脚本
-spec usage(#cfg{}, exit_code()) -> no_return().
usage(Cfg = #cfg{}, ExitCode) ->
    ScriptName = escript:script_name(),
    BaseName = filename:basename(ScriptName),
    desc_vsn(ScriptName),
    desc_title(BaseName, Cfg),
    desc_args(Cfg#cfg.args),
    desc_args(Cfg#cfg.sys),
    halt(ExitCode).

-spec cfg(string()) -> {ok, #cfg{}}.
cfg(File) ->
    do_cfg(File).

%%----------------------------------------------------
%% 内部私有
%%----------------------------------------------------
do_parse(_, _) -> ok.

desc_vsn(ScriptName) ->
    case script_options(ScriptName) of
        Options = [_ | _] ->
            Description = proplists:get_value(description, Options),
            Vsn = proplists:get_value(vsn, Options),
            io:format("~s (~s)~n", [Description, Vsn]);
        _ ->
            io:format("~n")
    end.

desc_title(BaseName, Cfg = #cfg{target = T, required = Req}) ->
    io:format("Usage: ~s", [BaseName]),
    do_desc_title(Cfg#cfg.args, #{target => Cfg#cfg.target, required => Cfg#cfg.required}),
    case T of
        T when is_bitstring(T) ->
            case Req of
                true ->
                    io:format(" <~s>", [T]);
                _ ->
                    io:format(" [~s]", [T])
            end,
            io:format("~n");
        _ ->
            io:format("~n")
    end,
    do_desc_title(Cfg#cfg.sys, #{sys => true, basename => BaseName, target => undefined, required => false}),
    io:format("~n").

do_desc_title([], _) -> ok;
do_desc_title([A = #arg{} | T], Args = #{sys := true, basename := BaseName}) ->
    io:format("       ~s ~s~n", [BaseName, parse_args(A)]),
    do_desc_title(T, Args);
do_desc_title([A = #arg{} | T], Args = #{}) ->
    io:format(" ~s", [parse_args(A)]),
    do_desc_title(T, Args).

%% ~s [-b | --base <FILENAME>] [-d | --debug] <FILENAME>~n
parse_args(#arg{required = R, short = S, long = L, arg_name = Names}) ->
    RNames = parse_arg_name(Names, " "),
    Pre = case {S, L} of
        {S, undefined} ->
            "-" ++ S;
        {undefined, L} ->
            "--" ++ L;
        {S, L} ->
            "-" ++ S ++ " | " ++ "--" ++ L
    end,
    case R of
        true ->
            "<" ++ Pre ++ RNames ++ ">";
        _ ->
            "[" ++ Pre ++ RNames ++ "]"
    end.

parse_arg_name([], _) -> "";
parse_arg_name([N], Acc) -> Acc ++ "<" ++ N ++ ">";
parse_arg_name([N | T], Acc) ->
    parse_arg_name(T, Acc ++ "<" ++ N ++ "> ").

desc_args([]) -> ok;
desc_args([#arg{desc = Desc, short = undefined, long = L} | T]) ->
    io:format("           ~-8s     ~s~n", ["--" ++ L, Desc]),
    desc_args(T);
desc_args([#arg{desc = Desc, short = S, long = undefined} | T]) ->
    io:format("       ~2.s,              ~s~n", ["-" ++ S, Desc]),
    desc_args(T);
desc_args([#arg{desc = Desc, short = S, long = L} | T]) ->
    io:format("       ~2.s, ~-8s     ~s~n", ["-" ++ S, "--" ++ L, Desc]),
    desc_args(T).

script_options(ScriptName) ->
    {ok, Sections} = escript:extract(ScriptName, []),
    Archive = proplists:get_value(archive, Sections),
    AppFile = lists:flatten(io_lib:format("~p/ebin/~p.app", [?MODULE, ?MODULE])),
    case zip:extract(Archive, [{file_list, [AppFile]}, memory]) of
        {ok, [{_, Binary}]} ->
            {ok, Tokens, _} = erl_scan:string(binary_to_list(Binary)),
            {ok, {application, ?MODULE, Options}} = erl_parse:parse_term(Tokens),
            Options;
        _ ->
            undefined
    end.

do_cfg(Config) ->
    case file:consult(Config) of
        {ok, TermList = [_ | _]} ->
            check_fromat_duplicate(TermList, []);
        Reason ->
            {error, Reason}
    end.

check_fromat_duplicate([], Acc) ->
    {ok, Acc};
check_fromat_duplicate([Term = {Key, _Value} | Left], Acc) ->
    case lists:keymember(Key, 1, Acc) of
        true -> {error, key_duplicate, Key};
        false -> check_fromat_duplicate(Left, [Term | Acc])
    end;
check_fromat_duplicate([Term | _], _) ->
    {error,format_error,Term}.

%%----------------------------------------------------
%% 测试用例
%%----------------------------------------------------
-include_lib("eunit/include/eunit.hrl").
-ifdef(TEST).
usage_test() ->
    Cfg = #cfg{
        desc = <<"This is a very important TEST information for\n all users, because we are asdf sghoe ghr HGS aoag geds.">>
        ,example = undefined
        ,target = <<"FILENAME">>
        ,required = true
        ,args = [
            #arg{
                desc = <<"Set original filename">>
                ,required = false
                ,short = "b"
                ,long = "base"
                ,arg_name = ["FILENAME"]
            }
            ,#arg{
                desc = <<"Enable debug output">>
                ,required = false
                ,short = "d"
                ,long = "debug" 
                ,arg_name = []
            }
        ]
        ,sys = [
            #arg{
                desc = <<"get some help for using">>
                ,required = true
                ,short = "h"
                ,long = "help"
            }
            ,#arg{
                desc = <<"WncvydZSLuxQJBKaRKC tflF ZFmvmcVxATlq">>
                ,required = true
                ,short = "v"
                ,arg_name = []
            }
        ]
    },
    usage(Cfg, ?EXIT_SUCCESS).
-endif.
