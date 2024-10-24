#!/bin/bash
# Script per avviare Erlang, compilare i moduli e avviare il sistema

erl -noshell -eval "compile:file(start_system), compile:file(node), compile:file(server), compile:file(visualizer), start_system:start(), halt()."
