%%% ocs.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2017 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This library module implements the public API for the
%%% 	{@link //ocs. ocs} application.
%%%
-module(ocs).
-copyright('Copyright (c) 2016 - 2017 SigScale Global Inc.').

%% export the ocs public API
-export([add_client/2, add_client/3, add_client/5, find_client/1,
		update_client/2, update_client/3, get_clients/0, delete_client/1,
		query_clients/6]).
-export([add_service/2, add_service/3, add_service/4, add_service/5,
		add_service/8, add_product/2, add_product/3, add_product/5,
		delete_product/1, get_products/0, query_product/4]).
-export([find_service/1, delete_service/1, get_services/0, query_service/3,
		find_product/1]).
-export([add_bucket/2, find_bucket/1, get_buckets/0, get_buckets/1,
		delete_bucket/1, query_bucket/3]).
-export([add_user/3, list_users/0, get_user/1, delete_user/1,
		query_users/3, update_user/3]).
-export([add_offer/1, find_offer/1, get_offers/0, delete_offer/1,
		query_offer/7]).
-export([add_pla/1, add_pla/2, find_pla/1, get_plas/0, delete_pla/1, query_table/6]).
-export([generate_password/0, generate_identity/0]).
-export([start/4, start/5]).
%% export the ocs private API
-export([normalize/1, subscription/4, end_period/2]).
-export([import/2, find_sn_network/2]).

-export_type([eap_method/0, match/0]).

-include("ocs.hrl").
-include_lib("inets/include/mod_auth.hrl").

-define(LOGNAME, radius_acct).
-define(CHUNKSIZE, 100).

%% support deprecated_time_unit()
-define(MILLISECOND, milli_seconds).
%-define(MILLISECOND, millisecond).

% calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}})
-define(EPOCH, 62167219200).

%%----------------------------------------------------------------------
%%  The ocs public API
%%----------------------------------------------------------------------

-spec add_client(Address, Secret) -> Result
	when
		Address :: inet:ip_address(),
		Secret :: string() | binary(),
		Result :: {ok, #client{}}.
%% @equiv add_client(Address, 3799, radius, Secret, true)
%% @doc Create an entry in the client table.
%%
add_client(Address, Secret) ->
	add_client(Address, 3799, radius, Secret, true).

-spec add_client(Address, Secret, PasswordRequired) -> Result
	when
		Address :: inet:ip_address(),
		Secret :: string() | binary(),
		PasswordRequired :: boolean(),
		Result :: {ok, #client{}}.
%% @equiv add_client(Address, 3799, radius, Secret, PasswordRequired)
add_client(Address, Secret, PasswordRequired) ->
	add_client(Address, 3799, radius, Secret, PasswordRequired).

-spec add_client(Address, Port, Protocol, Secret, PasswordRequired) -> Result
	when
		Address :: inet:ip_address(),
		Port :: inet:port_number() | undefined,
		Protocol :: atom() | undefined,
		Secret :: string() | binary() | undefined,
		PasswordRequired :: boolean(),
		Result :: {ok, # client{}}.
%% @doc Create an entry in the client table.
%%
add_client(Address, Port, Protocol, Secret, PasswordRequired) when is_list(Address) ->
	{ok, AddressTuple} = inet_parse:address(Address),
	add_client(AddressTuple, Port, Protocol, Secret, PasswordRequired);
add_client(Address, Port, Protocol, Secret, undefined) ->
	add_client(Address, Port, Protocol, Secret, true);
add_client({A, B, C, D} = Address, undefined, diameter, undefined, PasswordRequired)
		when A >= 1, A =< 255, B >= 0, C =< 255, C >= 0, D =< 255, D >= 1, A < 255,
		is_boolean(PasswordRequired) ->
	F = fun() ->
				TS = erlang:system_time(?MILLISECOND),
				N = erlang:unique_integer([positive]),
				R = #client{
						address = Address,
						protocol = diameter, last_modified = {TS, N},
						password_required = PasswordRequired},
				mnesia:write(R),
				R
	end,
	case mnesia:transaction(F) of
		{atomic, Client} ->
			{ok, Client};
		{aborted, Reason} ->
			exit(Reason)
	end;
add_client(Address, Port, Protocol, undefined, PasswordRequired) ->
	add_client(Address, Port, Protocol, generate_password(), PasswordRequired);
add_client(Address, Port, undefined, Secret, PasswordRequired) ->
	add_client(Address, Port, radius, Secret, PasswordRequired);
add_client(Address, undefined, Protocol, Secret, PasswordRequired) ->
	add_client(Address, 3799, Protocol, Secret, PasswordRequired);
add_client(Address, Port, Protocol, Secret, PasswordRequired) when is_list(Secret) ->
	add_client(Address, Port, Protocol, list_to_binary(Secret), PasswordRequired);
add_client({A, B, C, D} = Address, Port, radius, Secret, PasswordRequired)
		when A >= 1, A =< 255, B >= 0, C =< 255, C >= 0, D =< 255, D >= 1, A < 255,
		is_binary(Secret), is_boolean(PasswordRequired) ->
	F = fun() ->
				TS = erlang:system_time(?MILLISECOND),
				N = erlang:unique_integer([positive]),
				LM = {TS, N},
				R = #client{address = Address, port = Port,
						protocol = radius, secret = Secret,
						password_required = PasswordRequired,
						last_modified = LM},
				ok = mnesia:write(R),
				R
	end,
	case mnesia:transaction(F) of
		{atomic, Client} ->
			{ok, Client};
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec find_client(Address) -> Result
	when
		Address :: inet:ip_address(),
		Result :: {ok, #client{}} | {error, Reason}, 
		Reason :: not_found | term().
%% @doc Find a client by IP address.
%%
find_client(Address) when is_list(Address) ->
	{ok, AddressTuple} = inet_parse:address(Address),
	find_client(AddressTuple);
find_client(Address) when is_tuple(Address) ->
	F = fun() ->
				mnesia:read(client, Address, read)
	end,
	case mnesia:transaction(F) of
		{atomic, [#client{} = Client]} ->
			{ok, Client};
		{atomic, []} ->
			{error, not_found};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec update_client(Address, Password)-> Result
	when
		Address :: string() | inet:ip_address(),
		Password :: string() | binary(),
		Result :: ok | {error, Reason},
		Reason :: not_found | term().
%% @doc Update a client password.
update_client(Address, Password) when is_list(Address) ->
	{ok, AddressTuple} = inet_parse:address(Address),
	update_client(AddressTuple, Password);
update_client(Address, Password) when is_list(Password) ->
	update_client(Address, list_to_binary(Password));
update_client(Address, Password) ->
	F = fun() ->
				case mnesia:read(client, Address, write) of
					[Entry] ->
						TS = erlang:system_time(?MILLISECOND),
						N = erlang:unique_integer([positive]),
						NewEntry = Entry#client{secret = Password, last_modified = {TS,N}},
						mnesia:write(client, NewEntry, write);
					[] ->
						throw(not_found)
				end
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, {throw, Reason}} ->
			{error, Reason};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec update_client(Address, Port, Protocol)-> Result
	when
		Address :: string() | inet:ip_address(),
		Port :: inet:port_number() | undefined,
		Protocol :: radius | diameter,
		Result :: ok | {error, Reason},
		Reason :: not_found | term().
%% @doc Update client port and protocol.
update_client(Address, Port, Protocol) when is_list(Address) ->
	{ok, AddressTuple} = inet_parse:address(Address),
	update_client(AddressTuple, Port, Protocol);
update_client(Address, Port, Protocol) when is_tuple(Address),
		(((Protocol == radius) and is_integer(Port))
		or ((Protocol == diameter) and (Port == undefined))) ->
	F = fun() ->
				case mnesia:read(client, Address, write) of
					[Entry] ->
						TS = erlang:system_time(?MILLISECOND),
						N = erlang:unique_integer([positive]),
						NewEntry = Entry#client{port = Port, protocol = Protocol,
								last_modified = {TS, N}},
						mnesia:write(client, NewEntry, write);
					[] ->
						throw(not_found)
				end
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, {throw, Reason}} ->
			{error, Reason};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec get_clients() -> Result
	when
		Result :: [#client{}] | {error, Reason},
		Reason :: term().
%% @doc Get all clients.
get_clients()->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun(F, start, Acc) ->
				F(F, mnesia:select(client, MatchSpec,
						?CHUNKSIZE, read), Acc);
			(_F, '$end_of_table', Acc) ->
				lists:flatten(lists:reverse(Acc));
			(_F, {error, Reason}, _Acc) ->
				{error, Reason};
			(F,{Clients, Cont}, Acc) ->
				F(F, mnesia:select(Cont), [Clients | Acc])
	end,
	case mnesia:transaction(F, [F, start, []]) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, Result} ->
			Result
	end.

-spec delete_client(Client) -> ok
	when
		Client :: string() | inet:ip_address().
%% @doc Delete an entry from the  client table.
delete_client(Client) when is_list(Client) ->
	{ok, ClientT} = inet:parse_address(Client),
	delete_client(ClientT);
delete_client(Client) when is_tuple(Client) ->
	F = fun() ->
		mnesia:delete(client, Client, write)
	end,
	case mnesia:transaction(F) of
		{atomic, _} ->
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec query_clients(Cont, Address, Identifier, Port, Protocol, Secret) -> Result
	when
		Cont :: start | any(),
		Address :: Match,
		Identifier :: Match,
		Port :: Match,
		Protocol :: Match,
		Secret :: Match,
		Match :: {exact, string()} | {like, string()} | '_',
		Result :: {Cont1, [#client{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @hidden
query_clients(start, {Op, String}, Identifier, Port, Protocol, Secret)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	{MatchHead, MatchConditions}  = case lists:last(String) of
		$% when Op == like ->
			{AddressMatch, Conditions} = match_address(lists:droplast(String)),
			{#client{address = AddressMatch, _ = '_'}, Conditions};
		_ ->
			{ok, Address} = inet:parse_address(String),
			{#client{address = Address, _  = '_'}, []}
	end,
	query_clients1(start, MatchHead, MatchConditions,
			Identifier, Port, Protocol, Secret);
query_clients(start, '_', Identifier, Port, Protocol, Secret) ->
	MatchHead = #client{_ = '_'},
	query_clients1(start, MatchHead, [], Identifier, Port, Protocol, Secret);
query_clients(Cont, _Address, Identifier, Port, _Protocol, Secret) ->
	query_clients2(Cont, [], [], Identifier, Port, Secret).
%% @hidden
query_clients1(start, MatchHead, MatchConditions,
		Identifier, Port, {Op, String}, Secret)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	try
		case lists:last(String) of
			$% when Op == like ->
				match_protocol(lists:droplast(String));
			_ ->
				case String of
					"diameter" ->
						diameter;
					"DIAMETER" ->
						diameter;
					"radius" ->
						radius;
					"RADIUS" ->
						radius;
					_ ->
						throw(badarg)
				end
		end
	of
		Protocol ->
			query_clients2(start, MatchHead#client{protocol = Protocol},
					MatchConditions, Identifier, Port, Secret)
	catch
		throw:badarg ->
			{eof, []}
	end;
query_clients1(start, MatchHead, MatchConditions, Identifier, Port, '_', Secret) ->
	query_clients2(start, MatchHead, MatchConditions, Identifier, Port, Secret).
%% @hidden
query_clients2(start, MatchHead, MatchConditions, Identifier, Port, Secret) ->
	MatchSpec = [{MatchHead, MatchConditions, ['$_']}],
	F = fun() ->
			mnesia:select(client, MatchSpec, ?CHUNKSIZE, read)
	end,
	query_clients3(mnesia:ets(F), Identifier, Port, Secret);
query_clients2(Cont, _MatchHead, _MatchConditions, Identifier, Port, Secret) ->
	F = fun() ->
			mnesia:select(Cont)
	end,
	query_clients3(mnesia:ets(F), Identifier, Port, Secret).
%% @hidden
query_clients3({Clients, Cont}, '_', Port, Secret) ->
	query_clients4({Clients, Cont}, Port, Secret);
query_clients3({Clients, Cont}, {Op, String}, Port, Secret)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	F = case lists:last(String) of
		$% when Op == like ->
			Prefix = list_to_binary(lists:droplast(String)),
			Size = size(Prefix),
			fun(#client{identifier = Identifier}) ->
				case binary:part(Identifier, 0, Size) of
					Prefix ->
						true;
					_ ->
						false
				end
			end;
		_ ->
			ExactMatch = list_to_binary(String),
			fun(#client{identifier = Identifier}) when Identifier == ExactMatch ->
					true;
				(_) ->
					false
			end
	end,
	query_clients4({lists:filter(F, Clients), Cont}, Port, Secret);
query_clients3('$end_of_table', _Identifier, _Port, _Secret) ->
      {eof, []}.
%% @hidden
query_clients4({Clients, Cont}, '_', Secret) ->
	query_clients5({Clients, Cont}, Secret);
query_clients4({Clients, Cont}, {Op, String}, Secret)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	F = case lists:last(String) of
		$% when Op == like ->
			Prefix = lists:droplast(String),
			fun(#client{port = Port}) ->
					lists:prefix(Prefix, integer_to_list(Port))
			end;
		_ ->
			fun(#client{port = Port}) ->
					String == integer_to_list(Port)
			end
	end,
	query_clients5({lists:filter(F, Clients), Cont}, Secret).
%% @hidden
query_clients5({Clients, Cont}, '_') ->
	{Cont, Clients};
query_clients5({Clients, Cont}, {Op, String})
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	F = case lists:last(String) of
		$% when Op == like ->
			Prefix = list_to_binary(lists:droplast(String)),
			Size = size(Prefix),
			fun(#client{secret = Secret}) ->
				case binary:part(Secret, 0, Size) of
					Prefix ->
						true;
					_ ->
						false
				end
			end;
		_ ->
			ExactMatch = list_to_binary(String),
			fun(#client{secret = Secret}) when Secret == ExactMatch ->
					true;
				(_) ->
					false
			end
	end,
	{Cont, lists:filter(F, Clients)}.

get_products()->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun(F, start, Acc) ->
		F(F, mnesia:select(product, MatchSpec,
				?CHUNKSIZE, read), Acc);
		(_F, '$end_of_table', Acc) ->
				lists:flatten(lists:reverse(Acc));
		(_F, {error, Reason}, _Acc) ->
				{error, Reason};
		(F,{Products, Cont}, Acc) ->
				F(F, mnesia:select(Cont), [Products | Acc])
	end,
	case mnesia:transaction(F, [F, start, []]) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, Result} ->
			Result
	end.

-spec query_product(Cont, MatchId, MatchOffer, MatchService) -> Result
	when
		Cont :: start | any(),
		MatchId ::  Match,
		MatchOffer ::  Match,
		MatchService ::  Match,
		Match :: {exact, string()} | {like, string()} | '_',
		Result :: {Cont1, [#product{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query product
query_product(Cont, '_' = _MatchId, MatchOffer, MatchService) ->
	 MatchHead = #product{_ = '_'},
	query_product1(Cont, MatchHead, MatchOffer, MatchService);
query_product(Cont, {Op, String}, MatchOffer, MatchService)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead = case lists:last(String) of
		$% when Op == like ->
			Prefix = lists:droplast(String),
			#product{id = Prefix ++ '_', _ = '_'};
		_ ->
			#product{id = String, _ = '_'}
	end,
	query_product1(Cont, MatchHead, MatchOffer, MatchService).
%% @hidden
query_product1(Cont, MatchHead, '_', MatchService) ->
	MatchSpec = [{MatchHead, [], ['$_']}],
	query_product2(Cont, MatchSpec, MatchService);
query_product1(Cont, MatchHead, {Op, String} = _MatchOffer, MatchService)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead1 = case lists:last(String) of
		$% when Op == like ->
			Prefix = lists:droplast(String),
			MatchHead#product{product = Prefix ++ '_'};
		_ ->
			MatchHead#product{product = String}
	end,
	MatchSpec = [{MatchHead1, [], ['$_']}],
	query_product2(Cont, MatchSpec, MatchService).
%% @hidden
query_product2(start, MatchSpec, MatchService) ->
	F = fun() ->
		mnesia:select(product, MatchSpec, ?CHUNKSIZE, read)
	end,
	query_product3(mnesia:ets(F), MatchService);
query_product2(Cont, _MatchSpec, MatchService) ->
	F = fun() ->
		mnesia:select(Cont)
	end,
	query_product3(mnesia:ets(F), MatchService).
%% @hidden
query_product3({Products, Cont}, '_') ->
	{Cont, Products};
query_product3({Products, Cont}, {Op, String})
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	F1 = case lists:last(String) of
		$% when Op == like ->
			Prefix = list_to_binary(lists:droplast(String)),
			Size = size(Prefix),
			F2 = fun(<<P:Size/binary, _/binary>>) when P == Prefix ->
						true;
					(_) ->
						false
			end,
			fun(#product{service = Services}) ->
						lists:any(F2, Services)
			end;
		_ ->
			Service = list_to_binary(String),
			fun(#product{service = Services}) ->
						lists:member(Service, Services)
			end
	end,
	{Cont, lists:filter(F1, Products)};
query_product3('$end_of_table', _MatchService) ->
	{eof, []}.

-spec add_product(Offer, ServiceRefs) -> Result
	when
		Offer :: string(),
		ServiceRefs :: [ServiceRef],
		Result :: {ok, #product{}} | {error, Reason},
		ServiceRef :: binary(),
		Reason :: term().
%% @equiv add_product(Offer, undefined, undefined, Characteristics)
add_product(Offer, ServiceRefs) ->
	add_product(Offer, ServiceRefs, undefined, undefined, []).

-spec add_product(Offer, ServiceRefs, Characteristics) -> Result
	when
		Offer :: string(),
		ServiceRefs :: [ServiceRef],
		Characteristics :: [tuple()],
		ServiceRef :: binary(),
		Result :: {ok, #product{}} | {error, Reason},
		Reason :: term().
%% @equiv add_product(Offer, undefined, undefined, Characteristics)
add_product(Offer, ServiceRefs, Characteristics) ->
	add_product(Offer, ServiceRefs, undefined, undefined, Characteristics).

-spec add_product(OfferId, ServiceRefs, StartDate, EndDate, Characteristics) -> Result
	when
		OfferId :: string(),
		ServiceRefs :: [ServiceRef],
		StartDate :: undefined | pos_integer(),
		EndDate :: undefined | pos_integer(),
		Characteristics :: [tuple()],
		ServiceRef :: binary(),
		Result :: {ok, #product{}} | {error, Reason},
		Reason :: term().
%% @doc Add a product inventory subscription instance.
add_product(OfferId, ServiceRefs, StartDate, EndDate, Characteristics)
		when (is_integer(StartDate) orelse (StartDate == undefined)),
		(is_integer(EndDate) orelse (EndDate == undefined)),
		is_list(Characteristics), is_list(OfferId), is_list(ServiceRefs) ->
	F = fun() ->
			case mnesia:read(offer, OfferId, read) of
				[#offer{char_value_use = CharValueUse} = Offer] ->
					TS = erlang:system_time(?MILLISECOND),
					N = erlang:unique_integer([positive]),
					LM = {TS, N},
					Id = ocs_rest:etag(LM),
					F2 = fun(ServiceRef) ->
								case mnesia:read(service, ServiceRef, write) of
									[Service] ->
										ok = mnesia:write(Service#service{product = Id,
												last_modified = LM});
									_ ->
										exit(service_not_found)
								end
					end,
					ok = lists:foreach(F2, ServiceRefs),
					NewChars = default_chars(CharValueUse, Characteristics),
					Product1 = #product{id = Id, product = OfferId, start_date = StartDate,
							end_date = EndDate, characteristics = NewChars,
							service = ServiceRefs, last_modified = LM},
					{Product2, Buckets} = subscription(Product1, Offer, [], true),
					F3 = fun(#bucket{} = B) -> ok = mnesia:write(bucket, B, write) end,
					ok = lists:foreach(F3, Buckets),
					ok = mnesia:write(Product2),
					Product2;
				[] ->
					throw(offer_not_found)
			end
	end,
	case mnesia:transaction(F) of
		{atomic, Product} ->
			{ok, Product};
		{aborted, {throw, Reason}} ->
			{error, Reason};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec find_product(ProductRef) -> Result
	when
		ProductRef :: string(),
		Result :: {ok, Product} | {error, Reason},
		Product :: #product{},
		Reason :: not_found | term().
%% @doc Look up entry in product table
find_product(ProductRef) when is_list(ProductRef) ->
	F = fun() -> mnesia:read(product, ProductRef, read) end,
	case mnesia:transaction(F) of
		{atomic, []} ->
			{error, not_found};
		{atomic, [Product]} ->
			{ok, Product};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec delete_product(ProductRef) -> Result
	when
		ProductRef :: string(),
		Result :: ok.
%% @doc Delete an entry from product table
delete_product(ProductRef) when is_list(ProductRef) ->
	F1 = fun(#service{product = PRef}, _) when PRef == ProductRef ->
					throw(service_exsist);
			(_, Acc) ->
					Acc
	end,
	F2 = fun() ->
			[] = mnesia:foldl(F1, [], service),
			mnesia:delete(product, ProductRef, write)
	end,
	case mnesia:transaction(F2) of
		{atomic, _} ->
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec add_service(Identity, Password) -> Result
	when
		Identity :: string() | binary() | undefined,
		Password :: string() | binary() | undefined,
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: term().
%% @equiv add_service(Identity, Password, undefined, [], true, false)
add_service(Identity, Password) ->
	add_service(Identity, Password, active, undefined, [], [], true, false).

-spec add_service(Identity, Password, ProductRef) -> Result
	when
		Identity :: string() | binary() | undefined,
		Password :: string() | binary() | undefined,
		ProductRef :: string() | undefined,
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: term().
%% @equiv add_service(Identity, Password, ProductRef, [], true, false)
add_service(Identity, Password, ProductRef) ->
	add_service(Identity, Password, active, ProductRef, [], [], true, false).

-spec add_service(Identity, Password, ProductRef, Chars) -> Result
	when
		Identity :: string() | binary() | undefined,
		Password :: string() | binary() | undefined,
		ProductRef :: string() | undefined,
		Chars :: [tuple()],
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: term().
%% @equiv add_service(Identity, Password, ProductRef, Chars, [], true, false)
add_service(Identity, Password, ProductRef, Chars) ->
	add_service(Identity, Password, active, ProductRef, Chars, [], true, false).

-spec add_service(Identity, Password, ProductRef, Chars, Attributes) -> Result
	when
		Identity :: string() | binary() | undefined,
		Password :: string() | binary() | undefined,
		ProductRef :: string() | undefined,
		Chars :: [tuple()],
		Attributes :: radius_attributes:attributes() | binary(),
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: term().
%% @equiv add_service(Identity, Password, ProductRef, Chars, Attributes, true, false)
add_service(Identity, Password, ProductRef, Chars, Attributes) ->
	add_service(Identity, Password, active, ProductRef, Chars, Attributes, true, false).

-spec add_service(Identity, Password, State, ProductRef, Chars,
		Attributes, EnabledStatus, MultiSessions) -> Result
	when
		Identity :: string() | binary() | undefined,
		Password :: string() | binary() | undefined,
		State :: atom() | string() | undefined,
		ProductRef :: string() | undefined,
		Chars :: [tuple()] | undefined,
		Attributes :: radius_attributes:attributes() | binary(),
		EnabledStatus :: boolean() | undefined,
		MultiSessions :: boolean() | undefined,
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: term().
%% @doc Create an entry in the service table.
%%
%% 	Authentication will be done using `Password'. An optional list of
%% 	RADIUS `Attributes', to be returned in an `AccessRequest' response,
%% 	may be provided.  These attributes will overide any default values.
%%
%% 	`ProductRef' key for product inventory reference,
%%		`Enabled' status and `MultiSessions' status may be provided.
%%
add_service(Identity, Password, State, ProductRef,
		Chars, Attributes, EnabledStatus, undefined) ->
	add_service(Identity, Password, State, ProductRef,
			Chars, Attributes, EnabledStatus, false);
add_service(Identity, Password, State, ProductRef,
		Chars, Attributes, undefined, MultiSession) ->
	add_service(Identity, Password, State, ProductRef,
			Chars, Attributes, true, MultiSession);
add_service(Identity, Password, State, ProductRef,
		Chars, undefined, EnabledStatus, MultiSession) ->
	add_service(Identity, Password, State, ProductRef,
			Chars, [], EnabledStatus, MultiSession);
add_service(Identity, Password, State, ProductRef,
		undefined, Attributes, EnabledStatus, MultiSession) ->
	add_service(Identity, Password, State, ProductRef,
			[], Attributes, EnabledStatus, MultiSession);
add_service(Identity, Password, undefined, ProductRef,
		Chars, Attributes, EnabledStatus, MultiSession) ->
	add_service(Identity, Password, active, ProductRef,
			Chars, Attributes, EnabledStatus, MultiSession);
add_service(Identity, undefined, State, ProductRef,
		Chars, Attributes, EnabledStatus, MultiSession) ->
	add_service(Identity, ocs:generate_password(), State,
			ProductRef, Chars, Attributes, EnabledStatus, MultiSession);
add_service(Identity, Password, State, ProductRef, Chars,
		Attributes, EnabledStatus, MultiSession) when is_list(Identity) ->
	add_service(list_to_binary(Identity), Password, State,
			ProductRef, Chars, Attributes, EnabledStatus, MultiSession);
add_service(Identity, Password, State, ProductRef, Chars,
		Attributes, EnabledStatus, MultiSession) when is_list(Password) ->
	add_service(Identity, list_to_binary(Password), State,
			ProductRef, Chars, Attributes, EnabledStatus, MultiSession);
add_service(undefined, Password, State, ProductRef, Chars,
		Attributes, EnabledStatus, MultiSession) when is_binary(Password),
		is_list(Attributes), is_boolean(EnabledStatus),
		is_boolean(MultiSession) ->
	F1 = fun() ->
			F2 = fun F2(_, 0) ->
							mnesia:abort(retries);
						F2(Identity1, I) ->
							case mnesia:read(service, Identity1, write) of
								[] ->
									Identity1;
								[_] ->
									F2(list_to_binary(generate_identity()), I - 1)
							end
			end,
			Identity = F2(list_to_binary(generate_identity()), 5),
			add_service1(Identity, Password, State, ProductRef,
					Chars, Attributes, EnabledStatus, MultiSession)
	end,
	case mnesia:transaction(F1) of
		{atomic, Service} ->
			{ok, Service};
		{aborted, Reason} ->
			{error, Reason}
	end;
add_service(Identity, Password, State, ProductRef, Chars, Attributes,
		EnabledStatus, MultiSession) when is_binary(Identity), size(Identity) > 0,
		is_binary(Password), is_list(Attributes), is_boolean(EnabledStatus),
		is_boolean(MultiSession) ->
	F1 =  fun() ->
			add_service1(Identity, Password, State, ProductRef,
					Chars, Attributes, EnabledStatus, MultiSession)
	end,
	case mnesia:transaction(F1) of
		{atomic, Service} ->
			{ok, Service};
		{aborted, {throw, Reason}} ->
			{error, Reason};
		{aborted, Reason} ->
			{error, Reason}
	end.
%% @hidden
add_service1(Identity, Password, State, undefined,
		Chars, Attributes, EnabledStatus, MultiSession) ->
	Now = erlang:system_time(?MILLISECOND),
	N = erlang:unique_integer([positive]),
	LM = {Now, N},
	S1 = #service{name = Identity,
					password = Password,
					state = State,
					attributes = Attributes,
					enabled = EnabledStatus,
					multisession = MultiSession,
					characteristics = Chars,
					last_modified = LM},
	ok = mnesia:write(service, S1, write),
	S1;
add_service1(Identity, Password, State, ProductRef,
		Chars, Attributes, EnabledStatus, MultiSession) ->
	case mnesia:read(product, ProductRef, read) of
		[#product{service = ServiceRefs} = P1] ->
			Now = erlang:system_time(?MILLISECOND),
			N = erlang:unique_integer([positive]),
			LM = {Now, N},
			P2 = P1#product{service = [Identity | ServiceRefs],
					last_modified = LM},
			ok = mnesia:write(P2),
			S1 = #service{name = Identity,
							password = Password,
							state = State,
							product = ProductRef,
							attributes = Attributes,
							enabled = EnabledStatus,
							multisession = MultiSession,
							characteristics = Chars,
							last_modified = LM},
			ok = mnesia:write(service, S1, write),
			S1;
		[] ->
			throw(product_not_found)
	end.

-spec add_bucket(ProductRef, Bucket) -> Result
	when
		ProductRef :: string(),
		Bucket :: #bucket{},
		Result :: {ok, BucketBefore, BucketAfter} | {error, Reason},
		BucketBefore :: #bucket{},
		BucketAfter :: #bucket{},
		Reason :: term().
%% @doc Add a new bucket to bucket table or update exsiting bucket
add_bucket(ProductRef, #bucket{id = undefined} = Bucket) when is_list(ProductRef) ->
	F = fun() ->
		case mnesia:read(product, ProductRef, write) of
			[#product{balance = B} = P] ->
				BId = generate_bucket_id(),
				Bucket1  = Bucket#bucket{id = BId, product = [ProductRef]},
				ok = mnesia:write(bucket, Bucket1, write),
				Product = P#product{balance = lists:reverse([BId | B])},
				ok = mnesia:write(product, Product, write),
				{ok, undefined, Bucket1};
			[] ->
				throw(product_not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, {ok, OldBucket, NewBucket}} ->
			[ProdRef | _] = NewBucket#bucket.product,
			ocs_log:abmf_log(topup, undefined, NewBucket#bucket.id, cents, ProdRef, 0, 0,
				NewBucket#bucket.remain_amount, undefined, undefined, undefined, undefined, undefined, undefined, NewBucket#bucket.status),
			{ok, OldBucket, NewBucket};
		{aborted, Reason} ->
			{error, Reason}
	end;
add_bucket(ProductRef, #bucket{id = BId, product = ProdRef1,
		remain_amount = RAmount1, end_date = TD} = _Bucket)
		when is_list(ProductRef) ->
	F = fun() ->
		case mnesia:read(product, ProductRef, write) of
			[#product{balance = B} = P] ->
				case mnesia:read(bucket, BId, write) of
					[#bucket{product = ProdRef2,
							remain_amount = RAmount2} = Bucket2] ->
						ProdRef3 = ProdRef2 ++ [ProdRef1 -- ProdRef2],
						Bucket3  = Bucket2#bucket{id = BId, product = ProdRef3,
							remain_amount = RAmount2 + RAmount1, end_date = TD},
						ok = mnesia:write(bucket, Bucket3, write),
						case lists:any(fun(Id) when Id == BId -> true; (_) -> false end, B) of
							true ->
								Product = P#product{balance = lists:reverse([BId | B])},
								ok = mnesia:write(product, Product, write),
								{ok, Bucket2, Bucket3};
							false ->
								{ok, Bucket2, Bucket3}
						end;
					[] ->
						throw(bucket_not_found)
				end;
			[] ->
				throw(product_not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, {ok, OldBucket, NewBucket}} ->
			[ProdRef | _] = NewBucket#bucket.product,
			ocs_log:abmf_log(topup, undefined, NewBucket#bucket.id, NewBucket#bucket.units, ProdRef, RAmount1, OldBucket#bucket.remain_amount,
				NewBucket#bucket.remain_amount, undefined, undefined, undefined, undefined, undefined, undefined, NewBucket#bucket.status),
			{ok, OldBucket, NewBucket};
		{aborted, {throw, Reason}} ->
			{error, Reason};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec find_bucket(BucketId) -> Result
	when
		BucketId :: term(),
		Result :: {ok, Bucket} | {error, Reason},
		Bucket :: #bucket{},
		Reason :: not_found | term().
%% @doc Look up an entry in the bucket table.
find_bucket(BucketId) ->
	F = fun() -> mnesia:read(bucket, BucketId, read) end,
	case mnesia:transaction(F) of
		{atomic, [#bucket{} = B]} ->
			{ok, B};
		{atomic, []} ->
			{error, not_found};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec get_buckets() -> Result
	when
		Result :: Buckets | {error, Reason},
		Buckets :: [#bucket{}],
		Reason :: term().
%% @doc Get the all buckets product reference
get_buckets() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun F(start, Acc) ->
		F(mnesia:select(bucket, MatchSpec,
				?CHUNKSIZE, read), Acc);
		F('$end_of_table', Acc) ->
				lists:flatten(lists:reverse(Acc));
		F({error, Reason}, _Acc) ->
				{error, Reason};
		F({Buckets, Cont}, Acc) ->
				F(mnesia:select(Cont), [Buckets | Acc])
	end,
	case mnesia:transaction(F, [start, []]) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, Result} ->
			Result
	end.

-spec get_buckets(ProdRef) -> Result
	when
		ProdRef :: string(),
		Result :: [#bucket{}] | {error, Reason},
		Reason :: term().
%% @doc Get the all buckets for given product reference
get_buckets(ProdRef) when is_list(ProdRef) ->
	F = fun() ->
		case mnesia:read(product, ProdRef) of
			[#product{balance = []}] ->
				[];
			[#product{balance = BucketRefs}] ->
				MatchHead = #bucket{id = '$1', _ = '_'},
				MatchIds = [{'==', Id, '$1'} || Id <- BucketRefs],
				MatchConditions = [list_to_tuple(['or' | MatchIds])],
				mnesia:select(bucket, [{MatchHead, MatchConditions, ['$_']}]);
			[] ->
				throw(product_not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, Buckets} ->
			Buckets;
		{aborted, {throw, Reason}} ->
			{error, Reason};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec query_bucket(Cont, MatchId, MatchProduct) -> Result
	when
		Cont :: start | any(),
		MatchId :: Match,
		MatchProduct :: Match,
		Match :: {exact, string()} | {like, string()} | '_',
		Result :: {Cont1, [#bucket{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query bucket
query_bucket(Cont, '_' = _MatchId, MatchProduct) ->
	MatchSpec = [{'_', [], ['$_']}],
	query_bucket1(Cont, MatchSpec, MatchProduct);
query_bucket(Cont, {Op, Id}, MatchProduct)
		when is_list(Id), ((Op == exact) orelse (Op == like)) ->
	MatchSpec = case lists:last(Id) of
		$% when Op == like ->
			Prefix = lists:droplast(Id),
			MatchHead = #bucket{id = Prefix ++ '_', _ = '_'},
			[{MatchHead, [], ['$_']}];
		_ ->
			MatchHead = #bucket{id = Id, _ = '_'},
			[{MatchHead, [], ['$_']}]
	end,
	query_bucket1(Cont, MatchSpec, MatchProduct).
%% @hidden
query_bucket1(start, MatchSpec, MatchProduct) ->
	F = fun() ->
		mnesia:select(bucket, MatchSpec, ?CHUNKSIZE, read)
	end,
	query_bucket2(mnesia:ets(F), MatchProduct);
query_bucket1(Cont, _MatchSpec, MatchProduct) ->
	F = fun() ->
		mnesia:select(Cont)
	end,
	query_bucket2(mnesia:ets(F), MatchProduct).
%% @hidden
query_bucket2({Buckets, Cont}, '_') ->
	{Cont, Buckets};
query_bucket2({Buckets, Cont}, {Op, String})
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	F1 = case lists:last(String) of
		$% when Op == like ->
			Prefix = lists:droplast(String),
			fun(#bucket{product = Products}) ->
					F2 = fun(P) ->
							lists:prefix(Prefix, P)
					end,
					lists:any(F2, Products)
			end;
		_ ->
			fun(#bucket{product = Products}) ->
					lists:member(Products, String)
			end
	end,
	{Cont, lists:filter(F1, Buckets)};
query_bucket2('$end_of_table', _MatchProduct) ->
      {eof, []}.

-spec delete_bucket(BucketId) -> ok
	when
		BucketId :: term().
%% @doc Delete entry in the bucket table.
delete_bucket(BucketId) ->
	F = fun() ->
		case mnesia:read(bucket, BucketId, write) of
			[#bucket{product = ProdRefs}] ->
				delete_bucket1(BucketId, ProdRefs);
			[] ->
				throw(not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, {throw, Reason}} ->
			exit(Reason);
		{aborted, Reason} ->
			exit(Reason)
	end.
%% @hidden
delete_bucket1(BId, ProdRefs) ->
	F = fun(ProdRef) ->
			case mnesia:read(product, ProdRef, write) of
				[#product{balance = Balance} = P] ->
					ok = mnesia:write(P#product{balance = Balance -- [BId]}),
					true;
				[] ->
					true
			end
	end,
	true = lists:all(F, ProdRefs),
	ok = mnesia:delete(bucket, BId, write).

-spec find_service(Identity) -> Result 
	when
		Identity :: string() | binary(),
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: not_found | term().
%% @doc Look up an entry in the service table.
find_service(Identity) when is_list(Identity) ->
	find_service(list_to_binary(Identity));
find_service(Identity) when is_binary(Identity) ->
	F = fun() ->
				mnesia:read(service, Identity, read)
	end,
	case mnesia:transaction(F) of
		{atomic, [#service{} = Service]} ->
			{ok, Service};
		{atomic, []} ->
			{error, not_found};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec get_services() -> Result
	when
		Result :: [#service{}] | {error, Reason},
		Reason :: term().
%% @doc Get all entries in the service table.
get_services()->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun(F, start, Acc) ->
				F(F, mnesia:select(service, MatchSpec,
						?CHUNKSIZE, read), Acc);
			(_F, '$end_of_table', Acc) ->
				lists:flatten(lists:reverse(Acc));
			(_F, {error, Reason}, _Acc) ->
				{error, Reason};
			(F,{Services, Cont}, Acc) ->
				F(F, mnesia:select(Cont), [Services | Acc])
	end,
	case mnesia:transaction(F, [F, start, []]) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, Result} ->
			Result
	end.

-spec query_service(Cont, MatchId, MatchProduct) -> Result
	when
		Cont :: start | any(),
		MatchId :: Match,
		MatchProduct :: Match,
		Match :: {exact, string()} | {like, string()} | '_',
		Result :: {Cont1, [#service{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query services 
query_service(Cont, MatchId, '_') ->
	MatchSpec = [{'_', [], ['$_']}],
	query_service1(Cont, MatchSpec, MatchId);
query_service(Cont, MatchId, {Op, String} = _MatchProduct)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	Product = case lists:last(String) of
		$% when Op == like ->
			lists:droplast(String) ++ '_';
		_ ->
         String
	end,
	MatchHead = #service{product = Product, _ = '_'},
	MatchSpec = [{MatchHead, [], ['$_']}],
   query_service1(Cont, MatchSpec, MatchId).
%% @hidden
query_service1(start, MatchSpec, MatchId) ->
	F = fun() ->
			mnesia:select(service, MatchSpec, ?CHUNKSIZE, read)
	end,
	query_service2(mnesia:ets(F), MatchId);
query_service1(Cont, _MatchSpec, MatchId) ->
	F = fun() ->
         mnesia:select(Cont)
   end,
	query_service2(mnesia:ets(F), MatchId).
%% @hidden
query_service2({Services, Cont}, '_') ->
	{Cont, Services};
query_service2({Services, Cont}, {Op, String})
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	F = case lists:last(String) of
		$% when Op == like ->
			Prefix = list_to_binary(lists:droplast(String)),
			Size = size(Prefix),
			fun(#service{name = Name}) ->
					case binary:part(Name, 0, Size) of
						Prefix ->
							true;
						_ ->
							false
					end
			end;
		_ ->
         ExactMatch = list_to_binary(String),
			fun(#service{name = Name}) when Name == ExactMatch ->
					true;
				(_) ->	
					false
			end
	end,
	{Cont, lists:filter(F, Services)};
query_service2('$end_of_table', _MatchId) ->
		{eof, []}.

-spec delete_service(Identity) -> ok
	when
		Identity :: string() | binary().
%% @doc Delete an entry in the service table.
delete_service(Identity) when is_list(Identity) ->
	delete_service(list_to_binary(Identity));
delete_service(Identity) when is_binary(Identity) ->
	F = fun() ->
		case mnesia:read(service, Identity, write) of
			[#service{product = undefined}] ->
				mnesia:delete(service, Identity, write);
			[#service{product = ProdRef}] ->
				case mnesia:read(product, ProdRef, write) of
					[#product{service = ServiceRefs} = P] ->
						P1 = P#product{service = ServiceRefs -- [Identity]},
						ok = mnesia:write(P1),
						mnesia:delete(service, Identity, write);
					[] ->
						ok
				end;
			[] ->
				ok
		end
	end,
	case mnesia:transaction(F) of
		{atomic, _} ->
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec add_offer(Offer) -> Result
	when
		Offer :: #offer{},
		Result :: {ok, #offer{}} | {error, Reason},
		Reason :: validation_failed | term().
%% @doc Add a new entry in offer table.
add_offer(#offer{price = Prices} = Offer) when length(Prices) > 0 ->
	Fvala = fun(undefined) ->
				true;
			(#alteration{name = Name, type = one_time, period = undefined,
					amount = Amount}) when length(Name) > 0, is_integer(Amount) ->
				true;
			(#alteration{name = Name, type = recurring, period = Period,
					amount = Amount}) when length(Name) > 0, ((Period == hourly)
					or (Period == daily) or (Period == weekly)
					or (Period == monthly) or (Period == yearly)),
					is_integer(Amount) ->
				true;
			(#alteration{name = Name, type = usage, period = undefined,
					units = Units, size = Size, amount = Amount})
					when length(Name) > 0, ((Units == octets)
					or (Units == seconds) or (Units == messages)),
					is_integer(Size), Size > 0, is_integer(Amount) ->
				true;
			(#alteration{}) ->
				false
	end,
	Fvalp = fun(#price{name = Name, type = one_time, period = undefined,
					amount = Amount, alteration = Alteration})
					when length(Name) > 0, is_integer(Amount), Amount > 0 ->
				Fvala(Alteration);
			(#price{name = Name, type = recurring, period = Period,
					amount = Amount, alteration = Alteration})
					when length(Name) > 0, ((Period == hourly)
					or (Period == daily) or (Period == weekly)
					or (Period == monthly) or (Period == yearly)),
					is_integer(Amount), Amount > 0 ->
				Fvala(Alteration);
			(#price{name = Name, type = usage, units = Units,
					size = Size, amount = Amount, alteration = undefined})
					when length(Name) > 0, Units == messages, is_integer(Size),
					Size > 0, is_integer(Amount), Amount > 0 ->
				true;
			(#price{name = Name, type = usage, period = undefined,
					units = Units, size = Size,
					amount = Amount, alteration = Alteration})
					when length(Name) > 0, ((Units == octets)
					or (Units == seconds) or (Units == messages)),
					is_integer(Size), Size > 0, is_integer(Amount),
					Amount > 0 ->
				Fvala(Alteration);
			(#price{type = tariff, alteration = undefined,
					size = Size, units = Units, amount = Amount})
					when is_integer(Size), Size > 0, ((Units == octets)
					or (Units == seconds) or (Units == messages)),
					((Amount == undefined) or (Amount == 0)) ->
				true;
			(#price{}) ->
				false
	end,
	case lists:all(Fvalp, Prices) of
		true ->
			add_offer1(Offer);
		false ->
			{error, validation_failed}
	end;
add_offer(#offer{specification = undefined, bundle = L} = Offer)
		when length(L) > 0 ->
	add_offer1(Offer);
add_offer(#offer{specification = L, bundle = []} = Offer)
		when length(L) > 0 ->
	add_offer1(Offer).
%% @hidden
add_offer1(Offer) ->
	Fadd = fun() ->
		TS = erlang:system_time(?MILLISECOND),
		N = erlang:unique_integer([positive]),
		Offer1 = Offer#offer{last_modified = {TS, N}},
		ok = mnesia:write(offer, Offer1, write),
		Offer1
	end,
	case mnesia:transaction(Fadd) of
		{atomic, Offer2} ->
			{ok, Offer2};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec add_pla(Pla) -> Result
	when
		Pla :: #pla{},
		Result :: {ok, #pla{}} | {error, Reason},
		Reason :: validation_failed | term().
%% @doc Add a new entry in pricing logic algorithm table.
add_pla(#pla{} = Pla) ->
	F = fun() ->
		TS = erlang:system_time(?MILLISECOND),
		N = erlang:unique_integer([positive]),
		R = Pla#pla{last_modified = {TS, N}},
		ok = mnesia:write(pla, R, write),
		R 
	end,
	case mnesia:transaction(F) of
		{atomic, #pla{name = Name} = Pla1} ->
			case catch list_to_existing_atom(Name) of
				{'EXIT', _Reason} ->
					ok = ocs_gtt:new(list_to_atom(Name), []),
					{ok, Pla1};
				_ ->
					{ok, Pla1}
			end;
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec add_pla(Pla, File) -> Result
	when
		Pla :: #pla{},
		File :: file:filename(),
		Result :: {ok, #pla{}} | {error, Reason},
		Reason :: validation_failed | term().
%% @doc Add a new entry in pricing logic algorithm table.
%% 	Import table rows from CSV file.
add_pla(#pla{} = Pla, File) when is_list(File) ->
	case catch ocs_gtt:import(File) of
		ok ->
			Basename = filename:basename(File),
			Name = string:sub_string(Basename, 1, string:rchr(Basename, $.) - 1),
			add_pla(Pla#pla{name = Name});
		{'EXIT', Reason} ->
			{error, Reason}
	end.

-spec find_offer(OfferID) -> Result
	when
		OfferID :: string(),
		Result :: {ok, Offer} | {error, Reason},
		Offer :: #offer{},
		Reason :: term().
%% @doc Find offer by product id
find_offer(OfferID) ->
	F = fun() ->
		case mnesia:read(offer, OfferID) of
			[Entry] ->
				Entry;
			[] ->
				throw(not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, Offer} ->
			{ok, Offer};
		{aborted, {throw, not_found}} ->
			{error, not_found};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec get_offers() -> Result
	when
		Result :: [#offer{}] | {error, Reason},
		Reason :: term().
%% @doc Get all entries in the offer table.
get_offers() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun(F, start, Acc) ->
				F(F, mnesia:select(offer, MatchSpec,
						?CHUNKSIZE, read), Acc);
			(_F, '$end_of_table', Acc) ->
				lists:flatten(lists:reverse(Acc));
			(_F, {error, Reason}, _Acc) ->
				{error, Reason};
			(F,{Offer, Cont}, Acc) ->
				F(F, mnesia:select(Cont), [Offer | Acc])
	end,
	case mnesia:transaction(F, [F, start, []]) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, Result} ->
			Result
	end.

-spec delete_offer(OfferID) -> Result
	when
		OfferID :: string(),
		Result :: ok.
%% @doc Delete an entry from the offer table.
delete_offer(OfferID) ->
	F = fun() ->
		MatchSpec = [{'$1', [{'==', OfferID, {element, #product.product, '$1'}}], ['$1']}],
		case mnesia:select(product, MatchSpec) of
			[] ->
				mnesia:delete(offer, OfferID, write);
			_ ->
				throw(unable_to_delete)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, _} ->
			ok;
		{aborted, {throw, Reason}} ->
			exit(Reason);
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec query_offer(Cont, Name, Description, Status, SDT, EDT, Price) -> Result
	when
		Cont :: start | any(),
		Name :: Match,
		Description :: Match,
		Status :: Match,
		SDT :: Match,
		EDT:: Match,
		Price :: Match,
		Match :: {exact, string()} | {notexact, string()} | {like, string()} | '_',
		Result :: {Cont1, [#offer{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query offer entires
query_offer(Cont, '_' = _Name, Description, Status, STD, EDT, Price) ->
	MatchSpec = [{'_', [], ['$_']}],
	query_offer1(Cont, MatchSpec, Description, Status, STD, EDT, Price);
query_offer(Cont, {Op, String}, Description, Status, STD, EDT, Price)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	 MatchSpec = case lists:last(String) of
		$% when Op == like ->
			Prefix = lists:droplast(String),
			MatchHead = #offer{name = Prefix ++ '_', _ = '_'},
			[{MatchHead, [], ['$_']}];
		_ ->
			MatchHead = #offer{name = String, _ = '_'},
			[{MatchHead, [], ['$_']}]
	end,
	query_offer1(Cont, MatchSpec, Description, Status, STD, EDT, Price).
%% @hidden
query_offer1(start, MatchSpec, Description, Status, STD, EDT, Price) ->
	F = fun() ->
		mnesia:select(offer, MatchSpec, ?CHUNKSIZE, read)
	end,
	query_offer2(mnesia:ets(F), Description, Status, STD, EDT, Price);
query_offer1(Cont, _MatchSpec, Description, Status, STD, EDT, Price) ->
	F = fun() ->
		mnesia:select(Cont)
	end,
	query_offer2(mnesia:ets(F), Description, Status, STD, EDT, Price).
%% @hidden
query_offer2({Offers, Cont}, '_', '_', '_', '_', '_') ->
	{Cont, Offers};
query_offer2('$end_of_table', _Description, _Status, _STD, _EDT, _Price) ->
	{eof, []}.

-spec query_table(Cont, Name, Prefix, Description, Rate, LM) -> Result
	when
		Cont :: start | any(),
		Name :: undefined | '_' | atom(),
		Prefix :: undefined | '_' | string(),
		Description :: undefined | '_' | string(),
		Rate :: undefined | '_' | string(),
		LM :: undefined | '_' | tuple(),
		Result :: {Cont1, [#gtt{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query pricing logic algorithm entires
query_table(Cont, Name, Prefix, Description, Rate, undefined) ->
	query_table(Cont, Name, Prefix, Description, Rate, '_');
query_table(Cont, Name, Prefix, Description, undefined, LM) ->
	query_table(Cont, Name, Prefix, Description, '_', LM);
query_table(Cont, Name, Prefix, undefined, Rate, LM) ->
	query_table(Cont, Name, Prefix, '_', Rate, LM);
query_table(Cont, Name, undefined, Description, Rate, LM) ->
	query_table(Cont, Name, '_', Description, Rate, LM);
query_table(start, Name, Prefix, Description, Rate, LM) ->
	MatchHead = #gtt{num = Prefix, value = {Description, Rate, LM}},
	MatchSpec = MatchSpec = [{MatchHead, [], ['$_']}],
	F = fun() ->
		mnesia:select(Name, MatchSpec, read)
	end,
	case mnesia:transaction(F) of
		{atomic, Pla} ->
			query_table1(Pla, []);
		{aborted, Reason} ->
			{error, Reason}
	end;
query_table(eof, _Name, _Prefix, _Description, _Rate, _LM) ->
	{eof, []}.
%% @hidden
query_table1([], Acc) ->
	{eof, lists:reverse(Acc)};
query_table1(Pla, _Acc) ->
	{eof, Pla}.

-spec get_plas() -> Result
	when
		Result :: [#pla{}] | {error, Reason},
		Reason :: term().
%% @doc Get all entries in the pla table.
get_plas() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun(F, start, Acc) ->
				F(F, mnesia:select(pla, MatchSpec,
						?CHUNKSIZE, read), Acc);
			(_F, '$end_of_table', Acc) ->
				lists:flatten(lists:reverse(Acc));
			(_F, {error, Reason}, _Acc) ->
				{error, Reason};
			(F,{Pla, Cont}, Acc) ->
				F(F, mnesia:select(Cont), [Pla | Acc])
	end,
	case mnesia:transaction(F, [F, start, []]) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, Result} ->
			Result
	end.

-spec find_pla(ID) -> Result
	when
		ID :: string(),
		Result :: {ok, Pla} | {error, Reason},
		Pla :: #pla{},
		Reason :: term().
%% @doc Find pricing logic algorithm by id.
find_pla(ID) ->
	F = fun() ->
		case mnesia:read(pla, ID) of
			[Entry] ->
				Entry;
			[] ->
				throw(not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, Pla} ->
			{ok, Pla};
		{aborted, {throw, not_found}} ->
			{error, not_found};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec delete_pla(ID) -> Result
	when
		ID :: string(),
		Result :: ok.
%% @doc Delete an entry from the pla table.
delete_pla(ID) ->
	F = fun() ->
		mnesia:delete(pla, ID, write)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			{atomic, ok} = mnesia:delete_table(list_to_existing_atom(ID)),
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.

-type password() :: [50..57 | 97..104 | 106..107 | 109..110 | 112..116 | 119..122].
-spec generate_password() -> password().
%% @equiv generate_password(12)
generate_password() ->
	generate_password(12).

-spec generate_identity() -> string().
%% @equiv generate_identity(7)
generate_identity() ->
	generate_identity(7).

-spec start(Protocol, Type, Address, Port) -> Result
	when
		Protocol :: radius | diameter,
		Type :: auth | acct,
		Address :: inet:ip_address(),
		Port :: pos_integer(),
		Result :: {ok, Pid} | {error, Reason},
		Pid :: pid(),
		Reason :: term().
%% @equiv start(Type, Address, Port, [])
start(Protocol, Type, Address, Port) when is_tuple(Address), is_integer(Port) ->
	start(Protocol, Type, Address, Port, []).

-type eap_method() :: pwd | ttls.
-spec start(Protocol, Type, Address, Port, Options) -> Result
	when
		Protocol :: radius | diameter,
		Type :: auth | acct,
		Address :: inet:ip_address(),
		Port :: pos_integer(),
		Options :: [{eap_method_prefer, EapType} | {eap_method_order, EapTypes}],
		EapType :: eap_method(),
		EapTypes :: [eap_method()],
		Result :: {ok, Pid} | {error, Reason},
		Pid :: pid(),
		Reason :: term().
%% @doc Start a RADIUS/DIAMETER request handler.
start(Protocol, Type, Address, Port, Options) when is_tuple(Address),
		is_integer(Port), is_list(Options) ->
		gen_server:call(ocs, {start, Protocol, Type, Address, Port, Options}).

-spec add_user(Username, Password, Locale) -> Result
	when
		Username :: string(),
		Password :: string(),
		Locale :: string(),
		Result :: {ok, LastModified} | {error, Reason},
		LastModified :: {integer(), integer()},
		Reason :: user_exists | term().
%% @doc Add an HTTP user.
%% 	HTTP Basic authentication (RFC7617) is required with
%% 	`Username' and  `Password' used to construct the
%% 	`Authorization' header in requests.
%%
%% 	`Locale' is used to set the language for text in the web UI.
%% 	For English use `"en"', for Spanish use `"es'"..
%%
add_user(Username, Password, Locale) when is_list(Username),
		is_list(Password), is_list(Locale) ->
	add_user1(Username, Password, Locale, get_params()).
%% @hidden
add_user1(Username, Password, Locale, {Port, Address, Dir, Group}) ->
	add_user2(Username, Password, Locale,
			Address, Port, Dir, Group, ocs:get_user(Username));
add_user1(_, _, _, {error, Reason}) ->
	{error, Reason}.
%% @hidden
add_user2(Username, Password, Locale,
		Address, Port, Dir, Group, {error, no_such_user}) ->
	LM = {erlang:system_time(?MILLISECOND), erlang:unique_integer([positive])},
	NewUserData = [{last_modified, LM}, {locale, Locale}],
	add_user3(Username, Address, Port, Dir, Group, LM,
			mod_auth:add_user(Username, Password, NewUserData, Address, Port, Dir));
add_user2(_, _, _, _, _, _, _, {error, Reason}) ->
	{error, Reason};
add_user2(_, _, _, _, _, _, _, {ok, _}) ->
	{error, user_exists}.
%% @hidden
add_user3(Username, Address, Port, Dir, Group, LM, true) ->
	add_user4(LM, mod_auth:add_group_member(Group, Username, Address, Port, Dir));
add_user3(_, _, _, _, _, _, {error, Reason}) ->
	{error, Reason}.
%% @hidden
add_user4(LM, true) ->
	{ok, LM};
add_user4(_, {error, Reason}) ->
	{error, Reason}.

-spec list_users() -> Result
	when
		Result :: {ok, Users} | {error, Reason},
		Users :: [Username],
		Username :: string(),
		Reason :: term().
%% @doc List HTTP users.
%% @equiv  mod_auth:list_users(Address, Port, Dir)
list_users() ->
	list_users1(get_params()).
%% @hidden
list_users1({Port, Address, Dir, _}) ->
	mod_auth:list_users(Address, Port, Dir);
list_users1({error, Reason}) ->
	{error, Reason}.

-spec get_user(Username) -> Result
	when
		Username :: string(),
		Result :: {ok, User} | {error, Reason},
		User :: #httpd_user{},
		Reason :: term().
%% @doc Get an HTTP user record.
%% @equiv mod_auth:get_user(Username, Address, Port, Dir)
get_user(Username) ->
	get_user(Username, get_params()).
%% @hidden
get_user(Username, {Port, Address, Dir, _}) ->
	mod_auth:get_user(Username, Address, Port, Dir);
get_user(_, {error, Reason}) ->
	{error, Reason}.

-spec delete_user(Username) -> Result
	when
		Username :: string(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Delete an existing HTTP user.
delete_user(Username) ->
	delete_user1(Username, get_params()).
%% @hidden
delete_user1(Username, {Port, Address, Dir, GroupName}) ->
	delete_user2(GroupName, Username, Address, Port, Dir,
			mod_auth:delete_user(Username, Address, Port, Dir));
delete_user1(_, {error, Reason}) ->
	{error, Reason}.
%% @hidden
delete_user2(GroupName, Username, Address, Port, Dir, true) ->
	delete_user3(mod_auth:delete_group_member(GroupName,
			Username, Address, Port, Dir));
delete_user2(_, _, _, _, _, {error, Reason}) ->
	{error, Reason}.
%% @hidden
delete_user3(true) ->
	ok;
delete_user3({error, Reason}) ->
	{error, Reason}.

-spec update_user(Username, Password, Language) -> Result
	when
		Username :: string(),
		Password :: string(),
		Language :: string(),
		Result :: {ok, LM} | {error, Reason},
		LM :: {integer(), integer()},
		Reason :: term().
%% @hidden Update user password and language
update_user(Username, Password, Language) ->
	case get_user(Username) of
		{error, Reason} ->
			{error, Reason};
		{ok, #httpd_user{}} ->
			case delete_user(Username) of
				ok ->
					case add_user(Username, Password, Language) of
						{ok, LM} ->
							{ok, LM};
						{error, Reason} ->
							{error, Reason}
					end;
				{error, Reason} ->
					{error, Reason}
			end
	end.

-spec query_users(Cont, MatchId, MatchLocale) -> Result
	when
		Cont :: start | any(),
		MatchId :: Match,
		MatchLocale ::Match,
		Match :: {exact, string()} | {notexact, string()} | {like, string()},
		Result :: {Cont1, [#httpd_user{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query the user table.
query_users(start, '_', MatchLocale) ->
	MatchSpec = [{'_', [], ['$_']}],
	query_users1(MatchSpec, MatchLocale);
query_users(start, {Op, String} = _MatchId, MatchLocale)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchSpec = case lists:last(String) of
		$% when Op == like ->
			Prefix = lists:droplast(String),
			Username = {Prefix ++ '_', '_', '_', '_'},
			MatchHead = #httpd_user{username = Username, _ = '_'},
			[{MatchHead, [], ['$_']}];
		_ ->
			Username = {String, '_', '_', '_'},
			MatchHead = #httpd_user{username = Username, _ = '_'},
			[{MatchHead, [], ['$_']}]
	end,
	query_users1(MatchSpec, MatchLocale);
query_users(start, {notexact, String} = _MatchId, MatchLocale)
		when is_list(String) ->
	Username = {'$1', '_', '_', '_'},
	MatchHead = #httpd_user{username = Username, _ = '_'},
	MatchSpec = [{MatchHead, [{'/=', '$1', String}], ['$_']}],
	query_users1(MatchSpec, MatchLocale);
query_users(Cont, _MatchId, MatchLocale) when is_tuple(Cont) ->
	F = fun() ->
			mnesia:select(Cont)
	end,
	case mnesia:ets(F) of
		{Users, Cont1} ->
			query_users2(MatchLocale, Cont1, Users);
		'$end_of_table' ->
			{eof, []}
	end;
query_users(start, MatchId, MatchLocale) when is_tuple(MatchId) ->
	MatchCondition = [match_condition('$1', MatchId)],
	Username = {'$1', '_', '_', '_'},
	MatchHead = #httpd_user{username = Username, _ = '_'},
	MatchSpec = [{MatchHead, MatchCondition, ['$_']}],
	query_users1(MatchSpec, MatchLocale).
%% @hidden
query_users1(MatchSpec, MatchLocale) ->
	F = fun() ->
			mnesia:select(httpd_user, MatchSpec, ?CHUNKSIZE, read)
	end,
	case mnesia:ets(F) of
		{Users, Cont} ->
			query_users2(MatchLocale, Cont, Users);
		'$end_of_table' ->
			{eof, []}
	end.
%% @hidden
query_users2('_' = _MatchLocale, Cont, Users) ->
	{Cont, Users};
query_users2({exact, String} = _MatchLocale, Cont, Users)
		when is_list(String) ->
	F = fun(#httpd_user{user_data = UD}) ->
			case lists:keyfind(locale, 1, UD) of
				{_, String} ->
					true;
				_ ->
					false
			end
	end,
	{Cont, lists:filter(F, Users)};
query_users2({notexact, String} = _MatchLocale, Cont, Users)
		when is_list(String) ->
	F = fun(#httpd_user{user_data = UD}) ->
			case lists:keyfind(locale, 1, UD) of
				{_, String} ->
					false;
				_ ->
					true
			end
	end,
	{Cont, lists:filter(F, Users)};
query_users2({like, String} = _MatchLocale, Cont, Users)
		when is_list(String) ->
	F = case lists:last(String) of
		$% ->
			Prefix = lists:droplast(String),
			fun(#httpd_user{user_data = UD}) ->
					case lists:keyfind(locale, 1, UD) of
						{_, Locale} ->
							lists:prefix(Prefix, Locale);
						_ ->
							false
					end
			end;
		_ ->
			fun(#httpd_user{user_data = UD}) ->
					case lists:keyfind(locale, 1, UD) of
						{_, String} ->
							true;
						_ ->
							false
					end
			end
	end,
	{Cont, lists:filter(F, Users)}.

-record(roaming, {key, des, value}).

-spec import(File, Type) -> ok
	when
		File :: string(),
		Type :: data | voice | sms.
%% @doc Import roaming tables
import(File, Type) ->
	case file:read_file(File) of
		{ok, Binary} ->
			Basename = filename:basename(File),
			Table = list_to_atom(string:sub_string(Basename,
					1, string:rchr(Basename, $.) - 1)),
			import1(Table, Type, Binary, unicode:bom_to_encoding(Binary));
		{error, Reason} ->
			exit(file:format_error(Reason))
	end.
%% @hidden
import1(Table, Type, Binary, {latin1, 0}) ->
	import2(Table, Type, Binary);
import1(Table, Type, Binary, {utf8, Offset}) ->
	Length = size(Binary) - Offset,
	import2(Table, Type, binary:part(Binary, Offset, Length)).
%% @hidden
import2(Table, Type, Records) ->
	case mnesia:create_table(Table,
			[{disc_copies, [node() | nodes()]},
			{attributes, record_info(fields, roaming)},
			{record_name, roaming}]) of
		{atomic, ok} ->
			import3(Table, Type, Records);
		{aborted, {already_exists, Table}} ->
			case mnesia:clear_table(Table) of
				{atomic, ok} ->
					import3(Table, Type, Records);
				{aborted, Reason} ->
					exit(Reason)
			end;
		{aborted, Reason} ->
			exit(Reason)
	end.
%% @hidden
import3(Table, Type, Records) ->
	TS = erlang:system_time(?MILLISECOND),
	N = erlang:unique_integer([positive]),
	Split = binary:split(Records, [<<"\n">>, <<"\r">>, <<"\r\n">>], [global]),
	case mnesia:transaction(fun import4/5, [Table, Type, Split, {TS, N}, []]) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.
%%% @hidden
import4(Table, Type, [], _LM, Acc) ->
	F = fun(#roaming{} = G) -> mnesia:write(Table, G, write) end,
	lists:foreach(F, lists:flatten(Acc));
import4(Table, Type, [<<>> | T], LM, Acc) ->
	import4(Table, Type, T, LM, Acc);
import4(Table, Type, [Chunk | Rest], LM, Acc) ->
	case binary:split(Chunk, [<<"\"">>], [global]) of
		[Chunk] ->
			NewAcc = [import5(binary:split(Chunk, [<<",">>], [global]), Type, LM, []) | Acc],
			import4(Table, Type, Rest, LM, NewAcc);
		SplitChunks ->
			F = fun(<<$, , T/binary>>, AccIn) ->
						[T | AccIn];
					(<<>>, AccIn) ->
						[<<>> | AccIn];
					(C, AccIn) ->
						case binary:at(C, size(C) - 1) of
							$, ->
								[binary:part(C, 0, size(C) - 1) | AccIn];
							_ ->
								[C | AccIn]
						end
			end,
			AccOut = lists:foldl(F, [], SplitChunks),
			NewAcc = [import5(lists:reverse(AccOut), Type, LM, []) | Acc],
			import4(Table, Type, Rest, LM, NewAcc)
	end.
%%% @hidden
import5([<<>> | T], Type, LM, Acc) ->
	import5(T, Type, LM, [undefined | Acc]);
import5([H | T], Type, LM, Acc) ->
	import5(T, Type, LM, [binary_to_list(H) | Acc]);
import5([], Type, LM, Acc) when length(Acc) == 3 ->
	import6(lists:reverse(Acc), Type, LM);
import5([], _Type, _LM, _Acc) ->
	[].
%% @hidden
import6([Key, Desc, Rate], Type, LM) when Type == voice; Type == sms ->
	#roaming{key =list_to_binary(Key), des = Desc, value = Rate};
import6([Key, Desc, Rate], data, LM) ->
	#roaming{key =list_to_binary(Key), des = Desc, value = ocs_rest:millionths_in(Rate)}.

-spec find_sn_network(Table, Id) -> Roaming
	when
		Table :: atom(),
		Id :: string() | binary(),
		Roaming :: #roaming{}.
%% @doc Lookup roaming table
find_sn_network(Table, Id) when is_list(Id) ->
	find_sn_network(Table, list_to_binary(Id));
find_sn_network(Table, Id) ->
	F = fun() -> mnesia:read(Table, Id, read) end,
	case mnesia:transaction(F) of
		{atomic, [#roaming{} = R]} ->
			R;
		{atomic, []} ->
			exit(not_found);
		{aborted, Reason} ->
			exit(Reason)
	end.

%
%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec generate_password(Length) -> password()
	when 
		Length :: pos_integer().
%% @doc Generate a random uniform password.
%% @private
generate_password(Length) when Length > 0 ->
	Charset = charset(),
	NumChars = length(Charset),
	Random = crypto:strong_rand_bytes(Length),
	generate_password(Random, Charset, NumChars,[]).
%% @hidden
generate_password(<<N, Rest/binary>>, Charset, NumChars, Acc) ->
	CharNum = (N rem NumChars) + 1,
	NewAcc = [lists:nth(CharNum, Charset) | Acc],
	generate_password(Rest, Charset, NumChars, NewAcc);
generate_password(<<>>, _Charset, _NumChars, Acc) ->
	Acc.

-spec generate_identity(Length) -> string()
	when
		Length :: pos_integer().
%% @doc Generate a random uniform numeric identity.
%% @private
generate_identity(Length) when Length > 0 ->
	Charset = lists:seq($0, $9),
	NumChars = length(Charset),
	Random = crypto:strong_rand_bytes(Length),
	generate_identity(Random, Charset, NumChars,[]).
%% @hidden
generate_identity(<<N, Rest/binary>>, Charset, NumChars, Acc) ->
	CharNum = (N rem NumChars) + 1,
	NewAcc = [lists:nth(CharNum, Charset) | Acc],
	generate_identity(Rest, Charset, NumChars, NewAcc);
generate_identity(<<>>, _Charset, _NumChars, Acc) ->
	Acc.

-spec charset() -> Charset
	when
		Charset :: password().
%% @doc Returns the table of valid characters for passwords.
%% @private
charset() ->
	C1 = lists:seq($2, $9),
	C2 = lists:seq($a, $h),
	C3 = lists:seq($j, $k),
	C4 = lists:seq($m, $n),
	C5 = lists:seq($p, $t),
	C6 = lists:seq($w, $z),
	lists:append([C1, C2, C3, C4, C5, C6]).

-spec normalize(String) -> string()
	when
		String :: string().
%% @doc Strip non hex digits and convert to lower case.
%% @private
normalize(String) ->
	normalize(String, []).
%% @hidden
normalize([Char | T], Acc) when Char >= 48, Char =< 57 ->
	normalize(T, [Char | Acc]);
normalize([Char | T], Acc) when Char >= 97, Char =< 102 ->
	normalize(T, [Char | Acc]);
normalize([$A | T], Acc) ->
	normalize(T, [$a | Acc]);
normalize([$B | T], Acc) ->
	normalize(T, [$b | Acc]);
normalize([$C | T], Acc) ->
	normalize(T, [$c | Acc]);
normalize([$D | T], Acc) ->
	normalize(T, [$d | Acc]);
normalize([$E | T], Acc) ->
	normalize(T, [$e | Acc]);
normalize([$F | T], Acc) ->
	normalize(T, [$f | Acc]);
normalize([_ | T], Acc) ->
	normalize(T, Acc);
normalize([], Acc) ->
	lists:reverse(Acc).

-spec subscription(Product, Offer, Buckets, InitialFlag) -> Result
	when
		Product :: #product{},
		Offer :: #offer{},
		Buckets :: [#bucket{}],
		InitialFlag :: boolean(),
		Result :: {Product, Buckets}.
%% @private
subscription(Product, #offer{bundle = [], price = Prices} =
		_Offer, Buckets, InitialFlag) ->
	Now = erlang:system_time(?MILLISECOND),
	subscription(Product, Now, InitialFlag, Buckets, Prices);
subscription(#product{product = OfferId} = Product,
		#offer{name = OfferId, bundle = Bundled, price = Prices} = _Offer,
		Buckets, InitialFlag) when length(Bundled) > 0 ->
	Now = erlang:system_time(?MILLISECOND),
	F = fun(#bundled_po{name = P}, {Prod, B}) ->
				case mnesia:read(offer, P, read) of
					[Offer] ->
						subscription(Prod, Offer, B, InitialFlag);
					[] ->
						throw(offer_not_found)
				end
	end,
	{Product1, Buckets1} = lists:foldl(F, {Product, Buckets}, Bundled),
	subscription(Product1, Now, InitialFlag, Buckets1, Prices).
%% @hidden
subscription(#product{id = ProdRef} = Product, Now, true, Buckets,
		[#price{type = one_time, amount = Amount,
			alteration = undefined} | T]) ->
	NewBuckets = charge(ProdRef, Amount, Buckets),
	subscription(Product, Now, true, NewBuckets, T);
subscription(#product{id = ProdRef} = Product, Now, true,
		Buckets, [#price{type = one_time, amount = PriceAmount,
			alteration = #alteration{units = Units, size = Size,
			amount = AlterAmount}} | T]) ->
	N = erlang:unique_integer([positive]),
	NewBuckets = charge(ProdRef, PriceAmount + AlterAmount,
			[#bucket{id = generate_bucket_id(), product = [ProdRef],
				units = Units, remain_amount = Size, last_modified = {Now, N}}
				| Buckets]),
	subscription(Product, Now, true, NewBuckets, T);
subscription(Product, Now, false, Buckets, [#price{type = one_time} | T]) ->
	subscription(Product, Now, false, Buckets, T);
subscription(#product{id = ProdRef} = Product, Now, true, Buckets,
		[#price{type = usage, alteration = #alteration{type = one_time,
			units = Units, size = Size, amount = AlterationAmount}} | T]) ->
	N = erlang:unique_integer([positive]),
	NewBuckets = charge(ProdRef, AlterationAmount,
		[#bucket{id = generate_bucket_id(), units = Units,
			remain_amount = Size, product = [ProdRef], last_modified = {Now, N}}
			| Buckets]),
	subscription(Product, Now, true, NewBuckets, T);
subscription(Product, Now, false, Buckets,
		[#price{type = usage, alteration = #alteration{type = one_time}} | T]) ->
	subscription(Product, Now, false, Buckets, T);
subscription(#product{id = ProdRef, payment = Payments} = Product,
		Now, true, Buckets, [#price{type = recurring, period = Period,
		amount = Amount, name = Name, alteration = undefined} | T]) when
		Period /= undefined ->
	NewBuckets = charge(ProdRef, Amount, Buckets),
	NewPayments = [{Name, end_period(Now, Period)} | Payments],
	Product1 = Product#product{payment = NewPayments},
	subscription(Product1, Now, true, NewBuckets, T);
subscription(#product{id = ProdRef, payment = Payments} = Product, Now, false, Buckets,
		[#price{type = recurring, period = Period, amount = Amount,
			name = Name, alteration = undefined} | T]) when Period /= undefined ->
	{NewPayments, NewBuckets} = dues(Payments, Now, Buckets, Name, Period, Amount, ProdRef),
	Product1 = Product#product{payment = NewPayments},
	subscription(Product1, Now, false, NewBuckets, T);
subscription(#product{id = ProdRef, payment = Payments} = Product,
		Now, true, Buckets, [#price{type = recurring, period = Period,
			amount = Amount, alteration = #alteration{units = Units,
			size = Size, amount = AllowanceAmount}, name = Name} | T]) when
			(Period /= undefined) and ((Units == octets) orelse
			(Units == seconds) orelse  (Units == messages)) ->
	N = erlang:unique_integer([positive]),
	NewBuckets = charge(ProdRef, Amount + AllowanceAmount,
			[#bucket{id = generate_bucket_id(),
			units = Units, remain_amount = Size, product = [ProdRef],
			end_date = end_period(Now, Period), last_modified = {Now, N}}
			| Buckets]),
	NewPayments = [{Name, end_period(Now, Period)} | Payments],
	Product1 = Product#product{payment = NewPayments},
	subscription(Product1, Now, true, NewBuckets, T);
subscription(#product{id = ProdRef, payment = Payments} = Product,
		Now, false, Buckets, [#price{type = recurring, period = Period,
			amount = Amount, alteration = #alteration{units = Units, size = Size,
			amount = AllowanceAmount}, name = Name} | T]) when (Period /= undefined)
			and ((Units == octets) orelse (Units == seconds) orelse (Units == messages)) ->
	{NewPayments, NewBuckets1} = dues(Payments, Now, Buckets, Name, Period, Amount, ProdRef),
	N = erlang:unique_integer([positive]),
	NewBuckets2 = charge(ProdRef, AllowanceAmount,
			[#bucket{id = generate_bucket_id(),
			units = Units, remain_amount = Size, product = [ProdRef],
			end_date = end_period(Now, Period), last_modified = {Now, N}}
			| NewBuckets1]),
	Product1 = Product#product{payment = NewPayments},
	subscription(Product1, Now, false, NewBuckets2, T);
subscription(#product{id = ProdRef, payment = Payments} = Product, Now, true,
		Buckets, [#price{type = usage, alteration = #alteration{type = recurring,
		period = Period, units = Units, size = Size, amount = Amount}, name = Name}
		| T]) when Period /= undefined, Units == octets; Units == seconds; Units == messages ->
	N = erlang:unique_integer([positive]),
	NewBuckets = charge(ProdRef, Amount, [#bucket{id = generate_bucket_id(),
			units = Units, remain_amount = Size, product = [ProdRef],
			end_date = end_period(Now, Period), last_modified = {Now, N}}
			| Buckets]),
	NewPayments = [{Name, end_period(Now, Period)} | Payments],
	Product1 = Product#product{payment = NewPayments},
	subscription(Product1, Now, true, NewBuckets, T);
subscription(#product{id = ProdRef, payment = Payments}
		= Product, Now, false, Buckets, [#price{type = usage, name = Name,
		alteration = #alteration{type = recurring, period = Period, units = Units,
		size = Size, amount = Amount}} | T]) when Period /= undefined, Units == octets;
		Units == seconds; Units == messages ->
	{NewPayments, NewBuckets1} = dues(Payments, Now, Buckets, Name, Period, Amount, ProdRef),
	N = erlang:unique_integer([positive]),
	NewBuckets2 = charge(ProdRef, Amount, [#bucket{id = generate_bucket_id(),
			units = Units, remain_amount = Size, product = [ProdRef],
			end_date = end_period(Now, Period), last_modified = {Now, N}}
			| NewBuckets1]),
	NewPayments = [{Name, end_period(Now, Period)} | Payments],
	Product1 = Product#product{payment = NewPayments},
	subscription(Product1, Now, false, NewBuckets2, T);
subscription(Product, Now, InitialFlag, Buckets, [_H | T]) ->
	subscription(Product, Now, InitialFlag, Buckets, T);
subscription(Product, _Now, _, Buckets, []) ->
	NewBIds = [Id || #bucket{id = Id} <- Buckets],
	{Product#product{balance = NewBIds}, Buckets}.

%% @hidden
dues(Payments, Now, Buckets, PName, Period, Amount, ProdRef) ->
	dues(Payments, Now, Buckets, PName, Period, Amount, ProdRef, []).
%% @hidden
dues([{_, DueDate} = P | T], Now, Buckets, PName, Period, Amount, ProdRef, Acc) when DueDate > Now ->
	dues(T, Now, Buckets, PName, Period, Amount, ProdRef, [P | Acc]);
dues([{PName, DueDate} | T], Now, Buckets, PName, Period, Amount, ProdRef, Acc) ->
	NewBuckets = charge(ProdRef, Amount, Buckets),
	case end_period(DueDate, Period) of
		NextDueDate when NextDueDate < Now ->
			dues([{PName, NextDueDate} | T], Now,
					NewBuckets, PName, Period, Amount, ProdRef, Acc);
		NextDueDate ->
			dues(T, Now, NewBuckets, PName, Period,
					Amount, ProdRef, [{PName, NextDueDate} | Acc])
	end;
dues([P | T], Now, Buckets, PName, Period, Amount, ProdRef, Acc) ->
	dues(T, Now, Buckets, PName, Period, Amount, ProdRef, [P | Acc]);
dues([], _Now, Buckets, _PName, _Period, _Amount, _ProdRef, Acc) ->
	{lists:reverse(Acc), Buckets}.

-spec get_params() -> Result
	when
		Result :: {Port :: integer(), Address :: string(),
				Directory :: string(), Group :: string()}
				| {error, Reason :: term()}.
%% @doc Returns configurations details for currently running
%% {@link //inets. httpd} service.
%% @hidden
get_params() ->
	get_params(inets:services_info()).
%% @hidden
get_params({error, Reason}) ->
	{error, Reason};
get_params(ServicesInfo) ->
	get_params1(lists:keyfind(httpd, 1, ServicesInfo)).
%% @hidden
get_params1({httpd, _, HttpdInfo}) ->
	{_, Address} = lists:keyfind(bind_address, 1, HttpdInfo),
	{_, Port} = lists:keyfind(port, 1, HttpdInfo),
	get_params2(Address, Port, application:get_env(inets, services));
get_params1(false) ->
	{error, httpd_not_started}.
%% @hidden
get_params2(Address, Port, {ok, Services}) ->
	get_params3(Address, Port, lists:keyfind(httpd, 1, Services));
get_params2(_, _, undefined) ->
	{error, inet_services_undefined}.
%% @hidden
get_params3(Address, Port, {httpd, Httpd}) ->
	get_params4(Address, Port, lists:keyfind(directory, 1, Httpd));
get_params3(_, _, false) ->
	{error, httpd_service_undefined}.
%% @hidden
get_params4(Address, Port, {directory, {Directory, Auth}}) ->
	get_params5(Address, Port, Directory,
			lists:keyfind(require_group, 1, Auth));
get_params4(_, _, false) ->
	{error, httpd_directory_undefined}.
%% @hidden
get_params5(Address, Port, Directory, {require_group, [Group | _]}) ->
	{Port, Address, Directory, Group};
get_params5(_, _, _, false) ->
	{error, httpd_group_undefined}.

-spec charge(ProdRef, Amount, Buckets) -> Buckets
	when
		ProdRef :: string(),
		Amount :: non_neg_integer(),
		Buckets :: [#bucket{}].
%% @doc Charge `Amount' to `Buckets'.
%% @private
charge(ProdRef, Amount, Buckets) ->
	charge(ProdRef, Amount, Buckets, []).
%% @hidden
charge(_ProdRef, 0, T, Acc) ->
	lists:reverse(Acc) ++ T;
charge(_ProdRef, Amount, [#bucket{units = cents,
		remain_amount = Remain} = B | T], Acc) when Amount < Remain ->
	lists:reverse(Acc) ++ [B#bucket{remain_amount = Remain - Amount} | T];
charge(_ProdRef, Amount, [#bucket{units = cents,
		remain_amount = Remain} = B], Acc) ->
	lists:reverse([B#bucket{remain_amount = Remain - Amount} | Acc]);
charge(ProdRef, Amount, [H | T], Acc) ->
	charge(ProdRef, Amount, T, [H | Acc]);
charge(ProdRef, Amount, [], Acc) ->
	lists:reverse([#bucket{id = generate_bucket_id(),
			units = cents, remain_amount = - Amount,
			product = [ProdRef]} | Acc]).

%% @private 
generate_bucket_id() ->
	TS = erlang:system_time(?MILLISECOND),
	N = erlang:unique_integer([positive]),
	integer_to_list(TS) ++ "-" ++ integer_to_list(N).

-spec date(MilliSeconds) -> DateTime
	when
		MilliSeconds :: pos_integer(),
		DateTime :: calendar:datetime().
%% @doc Convert timestamp to date and time.
%% @private
date(MilliSeconds) when is_integer(MilliSeconds) ->
	Seconds = ?EPOCH + (MilliSeconds div 1000),
	calendar:gregorian_seconds_to_datetime(Seconds).

-spec end_period(StartTime, Period) -> EndTime
	when
		StartTime :: non_neg_integer(),
		Period :: hourly | daily | weekly | monthly | yearly,
		EndTime :: non_neg_integer().
%% @doc Calculate end of period.
%% @private
end_period(StartTime, Period) when is_integer(StartTime) ->
	end_period1(date(StartTime), Period).
%% @hidden
end_period1({Date, {23, Minute, Second}}, hourly) ->
	NextDay = calendar:date_to_gregorian_days(Date) + 1,
	EndDate = calendar:gregorian_days_to_date(NextDay),
	EndTime = {0, Minute, Second},
	gregorian_datetime_to_system_time({EndDate, EndTime}) - 1;
end_period1({Date, {Hour, Minute, Second}}, hourly) ->
	EndTime = {Hour + 1, Minute, Second},
	gregorian_datetime_to_system_time({Date, EndTime}) - 1;
end_period1({Date, Time}, daily) ->
	NextDay = calendar:date_to_gregorian_days(Date) + 1,
	EndDate = calendar:gregorian_days_to_date(NextDay),
	gregorian_datetime_to_system_time({EndDate, Time}) - 1;
end_period1({Date, Time}, weekly) ->
	NextDay = calendar:date_to_gregorian_days(Date) + 7,
	EndDate = calendar:gregorian_days_to_date(NextDay),
	gregorian_datetime_to_system_time({EndDate, Time}) - 1;
end_period1({{Year, 1, Day}, Time}, monthly)
		when Day > 28 ->
	NextDay = calendar:last_day_of_the_month(Year, 2),
	EndDate = {Year, 2, NextDay},
	gregorian_datetime_to_system_time({EndDate, Time}) - 1;
end_period1({{Year, 2, Day}, Time}, monthly) when Day < 28 ->
	EndDate = {Year, 3, Day},
	gregorian_datetime_to_system_time({EndDate, Time}) - 1;
end_period1({{Year, 2, Day}, Time}, monthly) ->
	EndDate = case calendar:last_day_of_the_month(Year, 2) of
		Day ->
			{Year, 3, 31};
		_ ->
			{Year, 3, Day}
	end,
	gregorian_datetime_to_system_time({EndDate, Time}) - 1;
end_period1({{Year, 3, 31}, Time}, monthly) ->
	gregorian_datetime_to_system_time({{Year, 4, 30}, Time}) - 1;
end_period1({{Year, 4, 30}, Time}, monthly) ->
	gregorian_datetime_to_system_time({{Year, 5, 31}, Time}) - 1;
end_period1({{Year, 5, 31}, Time}, monthly) ->
	gregorian_datetime_to_system_time({{Year, 6, 30}, Time}) - 1;
end_period1({{Year, 6, 31}, Time}, monthly) ->
	gregorian_datetime_to_system_time({{Year, 7, 31}, Time}) - 1;
end_period1({{Year, 8, 31}, Time}, monthly) ->
	gregorian_datetime_to_system_time({{Year, 9, 30}, Time}) - 1;
end_period1({{Year, 9, 30}, Time}, monthly) ->
	gregorian_datetime_to_system_time({{Year, 10, 31}, Time}) - 1;
end_period1({{Year, 10, 30}, Time}, monthly) ->
	gregorian_datetime_to_system_time({{Year, 11, 30}, Time}) - 1;
end_period1({{Year, 11, 30}, Time}, monthly) ->
	gregorian_datetime_to_system_time({{Year, 12, 31}, Time}) - 1;
end_period1({{Year, 12, Day}, Time}, monthly) ->
	EndDate = {Year + 1, 1, Day},
	gregorian_datetime_to_system_time({EndDate, Time}) - 1;
end_period1({{Year, Month, Day}, Time}, monthly) ->
	EndDate = {Year, Month + 1, Day},
	gregorian_datetime_to_system_time({EndDate, Time}) - 1;
end_period1({{Year, Month, Day}, Time}, yearly) ->
	EndDate = {Year + 1, Month, Day},
	gregorian_datetime_to_system_time({EndDate, Time}) - 1.

-spec default_chars(CharValueUse, ReqChars) -> NewChars
	when
		CharValueUse:: [#char_value_use{}],
		ReqChars :: [tuple()],
		NewChars :: [tuple()].
%% @doc Add default characteristic values.
%% @hidden
default_chars([#char_value_use{name = Name, values = Values} | T], Acc) ->
	case lists:keymember(Name, 1, Acc) of
		true ->
			default_chars(T, Acc);
		false ->
			case default_chars1(Values) of
				undefined ->
					default_chars(T, Acc);
				Value ->
					default_chars(T, [{Name, Value} | Acc])
			end
	end;
default_chars([], Acc) ->
	lists:reverse(Acc).
%% @hidden
default_chars1([#char_value{default = true, value = Value} | _]) ->
	Value;
default_chars1([_ | T]) ->
	default_chars1(T);
default_chars1([]) ->
	undefined.

-spec gregorian_datetime_to_system_time(DateTime) -> MilliSeconds
	when
		DateTime :: tuple(),
		MilliSeconds :: pos_integer().
%% @doc Convert gregorian datetime to system time in milliseconds.
%% @hidden
gregorian_datetime_to_system_time(DateTime) ->
	(calendar:datetime_to_gregorian_seconds(DateTime) - ?EPOCH) * 1000.

-type match() :: {exact, term()} | {notexact, term()} | {lt, term()}
		| {lte, term()} | {gt, term()} | {gte, term()} | {regex, term()}
		| {like, [term()]} | {notlike, [term()]} | {in, [term()]}
		| {notin, [term()]} | {contains, [term()]} | {notcontain, [term()]}
		| {containsall, [term()]} | '_'.

-spec match_condition(MatchVariable, Match) -> MatchCondition
	when
		MatchVariable :: atom(), % '$<number>'
		Match :: {exact, term()} | {notexact, term()} | {lt, term()}
				| {lte, term()} | {gt, term()} | {gte, term()},
		MatchCondition :: {GuardFunction, MatchVariable, Term},
		Term :: any(),
		GuardFunction :: '=:=' | '=/=' | '<' | '=<' | '>' | '>='.
%% @doc Convert REST query patterns to Erlang match specification conditions.
%% @hidden
match_condition(Var, {exact, Term}) ->
	{'=:=', Var, Term};
match_condition(Var, {notexact, Term}) ->
	{'=/=', Var, Term};
match_condition(Var, {lt, Term}) ->
	{'<', Var, Term};
match_condition(Var, {lte, Term}) ->
	{'=<', Var, Term};
match_condition(Var, {gt, Term}) ->
	{'>', Var, Term};
match_condition(Var, {gte, Term}) ->
	{'>=', Var, Term}.

-spec match_address(String) -> Result
	when
		String :: string(),
		Result ::{MatchAddress, MatchConditions},
		MatchAddress :: tuple(),
		MatchConditions :: [tuple()].
%% @doc Construct match specification for IP address.
%% @hidden
match_address(String) ->
	Ns = [list_to_integer(N) || N <- string:tokens(String, [$.])],
	match_address1(lists:reverse(Ns)).
%% @hidden
match_address1([N | T]) when N >= 100 ->
	match_address2(T, [N], []);
match_address1([N | T]) when N >= 10 ->
	match_address2(T, ['$1'], [{'or', {'==', '$1', N},
			{'and', {'>=', '$1', N * 10}, {'<', '$1', (N + 1) * 10}}}]);
match_address1([N | T]) ->
	match_address2(T, ['$1'], [{'or', {'==', '$1', N},
			{'and', {'>=', '$1', N * 10}, {'<', '$1', (N + 1) * 10}},
			{'and', {'>=', '$1', N * 100}, {'<', '$1', (N + 1) * 100}}}]).
%% @hidden
match_address2(T, Head, Conditions) ->
	Head1 = lists:reverse(T) ++ Head,
	Head2 = Head1 ++ lists:duplicate(4 - length(Head1), '_'),
	{list_to_tuple(Head2), Conditions}.

%% @hidden
match_protocol(Prefix) ->
	case lists:prefix(Prefix, "diameter") of
		true ->
			diameter;
		false ->
			match_protocol1(Prefix)
	end.
%% @hidden
match_protocol1(Prefix) ->
	case lists:prefix(Prefix, "DIAMETER") of
		true ->
			diameter;
		false ->
			match_protocol2(Prefix)
	end.
%% @hidden
match_protocol2(Prefix) ->
	case lists:prefix(Prefix, "radius") of
		true ->
			radius;
		false ->
			match_protocol3(Prefix)
	end.
%% @hidden
match_protocol3(Prefix) ->
	case lists:prefix(Prefix, "RADIUS") of
		true ->
			radius;
		false ->
			throw(badmatch)
	end.

