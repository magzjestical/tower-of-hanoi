% Tower of Hanoi - Prolog backend (SWI-Prolog)
% Run:  swipl server.pl   then open http://localhost:8080
%
% A game state is a list of three pegs, each a list of disks with the
% TOP disk first, e.g. [[1,2,3],[],[]]. Disk 1 is the smallest.

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).
:- use_module(library(lists)).

:- initialization(main, main).

:- dynamic base_dir/1.
:- prolog_load_context(directory, D), assertz(base_dir(D)).

:- multifile user:file_search_path/2.
user:file_search_path(hanoi, D) :- base_dir(D).

:- http_handler(root(.),         page('index.html'),   []).
:- http_handler(root(design2),   page('design2.html'), []).
:- http_handler(root(design3),   page('design3.html'), []).
:- http_handler(root('hanoi.js'),page('hanoi.js'),     []).
:- http_handler(root(api/new),   api_new,   [method(post)]).
:- http_handler(root(api/move),  api_move,  [method(post)]).
:- http_handler(root(api/solve), api_solve, [method(post)]).

main :-
    Port = 8080,
    http_server(http_dispatch, [port(Port)]),
    format("Tower of Hanoi running at http://localhost:~w~n", [Port]),
    thread_get_message(_).

page(File, Request) :-
    http_reply_file(hanoi(File), [], Request).

% ---------- Game logic ----------

% apply_move(+State0, +FromPeg, +ToPeg, -State): legal moves only.
apply_move(S0, F, T, S) :-
    F \== T,
    nth0(F, S0, [D|FR]),
    nth0(T, S0, TR),
    (   TR == []
    ;   TR = [X|_], D < X
    ),
    set_nth(S0, F, FR, S1),
    set_nth(S1, T, [D|TR], S).

set_nth(L0, I, V, L) :-
    nth0(I, L0, _, Rest),
    nth0(I, L, V, Rest).

peg_of(K, S, P) :-
    nth0(P, S, Peg),
    memberchk(K, Peg), !.

% solve_to(+K, +Target, +S0, -S, -Moves): optimal moves that bring
% disks 1..K onto Target, from ANY legal state.
solve_to(0, _, S, S, []) :- !.
solve_to(K, T, S0, S, Moves) :-
    peg_of(K, S0, P),
    K1 is K - 1,
    (   P =:= T
    ->  solve_to(K1, T, S0, S, Moves)
    ;   O is 3 - P - T,
        solve_to(K1, O, S0, S1, M1),
        apply_move(S1, P, T, S2),
        solve_to(K1, T, S2, S, M3),
        append(M1, [move(P, T)|M3], Moves)
    ).

disk_count(S, N) :- maplist(length, S, Ls), sum_list(Ls, N).

% ---------- API ----------

state_reply(S) :-
    disk_count(S, N),
    solve_to(N, 2, S, _, Ms),
    length(Ms, Rem),
    Opt is (1 << N) - 1,
    (   S = [[], [], [_|_]] -> Won = true ; Won = false ),
    reply_json_dict(_{ok: true, pegs: S, remaining: Rem,
                      optimal: Opt, won: Won}).

api_new(Request) :-
    http_read_json_dict(Request, D),
    N = D.n,
    (   integer(N), N >= 1, N =< 8
    ->  numlist(1, N, Disks),
        state_reply([Disks, [], []])
    ;   reply_json_dict(_{ok: false, error: "Choose between 1 and 8 disks."})
    ).

api_move(Request) :-
    http_read_json_dict(Request, D),
    S0 = D.pegs, F = D.from, T = D.to,
    (   catch(apply_move(S0, F, T, S), _, fail)
    ->  state_reply(S)
    ;   reply_json_dict(_{ok: false,
            error: "Illegal move: a bigger disk can’t sit on a smaller one."})
    ).

api_solve(Request) :-
    http_read_json_dict(Request, D),
    S0 = D.pegs,
    disk_count(S0, N),
    solve_to(N, 2, S0, _, Ms),
    findall(_{from: A, to: B}, member(move(A, B), Ms), Moves),
    reply_json_dict(_{ok: true, moves: Moves}).
