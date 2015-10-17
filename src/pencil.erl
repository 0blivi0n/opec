%%
%% Copyright 2015 Joaquim Rocha <jrocha@gmailbox.org>
%% 
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

-module(pencil).

-include("pencil.hrl").
-include_lib("oblivion/include/oblivion_protocol.hrl").

-export([start_link/1]).

-export([put/3, put/4]).
-export([get/2]).
-export([delete/2, delete/3]).
-export([version/2]).
-export([size/1]).
-export([flush/1]).
-export([caches/0]).
-export([keys/1]).

%% ====================================================================
%% API functions
%% ====================================================================

start_link(Args) ->
	Server = proplists:get_value(server, Args),
	Port = proplists:get_value(port, Args),
	mec:open(Server, Port).

put(Cache, Key, Value) when is_binary(Cache) andalso is_binary(Key) ->
	Json = jsondoc:ensure(Value),
	Response = call(?PUT_CMD, [<<"caches">>, Cache, <<"keys">>, Key], [], Json),
	process(?PUT_CMD, Response).

put(Cache, Key, Value, Version) when is_binary(Cache) andalso is_binary(Key) ->
	Params = [{?VERSION_TAG, Version}],
	Json = jsondoc:ensure(Value),
	Response = call(?PUT_CMD, [<<"caches">>, Cache, <<"keys">>, Key], Params, Json),
	process(?PUT_CMD, Response).

get(Cache, Key) when is_binary(Cache) andalso is_binary(Key) ->
	Response = call(?GET_CMD, [<<"caches">>, Cache, <<"keys">>, Key]),
	process(?GET_CMD, Response).

delete(Cache, Key) when is_binary(Cache) andalso is_binary(Key) ->
	Response = call(?DELETE_CMD, [<<"caches">>, Cache, <<"keys">>, Key]),
	process(?DELETE_CMD, Response).

delete(Cache, Key, Version) when is_binary(Cache) andalso is_binary(Key) ->
	Params = [{?VERSION_TAG, Version}],
	Response = call(?DELETE_CMD, [<<"caches">>, Cache, <<"keys">>, Key], Params),
	process(?DELETE_CMD, Response).

version(Cache, Key) when is_binary(Cache) andalso is_binary(Key) ->
	Response = call(?VERSION_CMD, [<<"caches">>, Cache, <<"keys">>, Key]),
	process(?VERSION_CMD, Response).

size(Cache) when is_binary(Cache) ->
	Response = call(?GET_CMD, [<<"caches">>, Cache, <<"keys">>]),
	process(?SIZE_CMD, Response).	

flush(Cache) when is_binary(Cache) ->
	Response = call(?DELETE_CMD, [<<"caches">>, Cache, <<"keys">>]),
	process(?FLUSH_CMD, Response).	

caches() ->
	Response = call(?GET_CMD, [<<"caches">>]),
	process(?CACHES_CMD, Response).		

keys(Cache) when is_binary(Cache) ->
	Params = [{?LIST_TAG, true}],
	Response = call(?GET_CMD, [<<"caches">>, Cache, <<"keys">>], Params),
	process(?KEYS_CMD, Response).	

%% ====================================================================
%% Internal functions
%% ====================================================================

process(_Cmd, Error = {error, _Reason}) -> Error;
process(Cmd, {ok, Status, Params, Payload}) ->
	process_response(Cmd, Status, Params, Payload).

% GET
process_response(?GET_CMD, 200, Params, Payload) ->
	{_, Version} = lists:keyfind(?VERSION_TAG, 1, Params),
	{ok, Payload, Version};
% PUT
process_response(?PUT_CMD, 201, Params, _Payload) ->
	{_, Version} = lists:keyfind(?VERSION_TAG, 1, Params),
	{ok, Version};
% DELETE
process_response(?DELETE_CMD, 200, _Params, _Payload) -> ok;
% VERSION
process_response(?VERSION_CMD, 200, Params, _Payload) -> 
	{_, Version} = lists:keyfind(?VERSION_TAG, 1, Params),
	{ok, Version};
% SIZE
process_response(?SIZE_CMD, 200, _Params, Size) -> 
	{ok, Size};
% FLUSH
process_response(?FLUSH_CMD, 202, _Params, _Payload) -> ok; 
% KEY LIST
process_response(?KEYS_CMD, 200, _Params, Payload) -> 
	List = jsondoc:get_value(<<"keys">>, Payload),
	{ok, List};
% CACHE LIST
process_response(?CACHES_CMD, 200, _Params, Payload) -> 
	CacheList = jsondoc_query:select(Payload, [<<"caches">>, <<"cache">>]),
	{ok, CacheList};
% -else-
process_response(_Cmd, _Status, _Params, empty) -> {error, invalid_response};
process_response(_Cmd, _Status, _Params, Payload) -> process_error(Payload).

process_error(Error) ->
	Reason = jsondoc:get_value(?ERROR_REASON_TAG, Error),
	{error, Reason}.

call(Operation, Resource) ->
	poolboy:transaction(?MODULE, fun(Worker) ->
				mec:call(Worker, Operation, Resource)
		end).

call(Operation, Resource, Params) ->
	poolboy:transaction(?MODULE, fun(Worker) ->
				mec:call(Worker, Operation, Resource, Params)
		end).

call(Operation, Resource, Params, Payload) ->
	poolboy:transaction(?MODULE, fun(Worker) ->
				mec:call(Worker, Operation, Resource, Params, Payload)
		end).