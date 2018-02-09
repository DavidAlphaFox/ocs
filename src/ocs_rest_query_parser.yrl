Header
"%%% vim: ts=3: "
"%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
"%%% @copyright 2018 SigScale Global Inc."
"%%% @end"
"%%% Licensed under the Apache License, Version 2.0 (the \"License\");"
"%%% you may not use this file except in compliance with the License."
"%%% You may obtain a copy of the License at"
"%%%"
"%%%     http://www.apache.org/licenses/LICENSE-2.0"
"%%%"
"%%% Unless required by applicable law or agreed to in writing, software"
"%%% distributed under the License is distributed on an \"AS IS\" BASIS,"
"%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied."
"%%% See the License for the specific language governing permissions and"
"%%% limitations under the License."
"%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
"%%% @doc This library module implements a parser for TM Forum REST API"
"%%% 	Advanced Attribute Filtering Pattern query format in the"
"%%% 	{@link //ocs. ocs} application."
"%%%"
"%%% 	This module is generated with {@link //parsetools/yecc. yecc}"
"%%% 	from `{@module}.yrl'."
"%%%"
"%%% @author Vance Shipley <vances@sigscale.org>"
"%%% @reference Advanced Attribute Filtering Pattern for REST APIs"
"%%% (<a href=\"https://projects.tmforum.org/jira/browse/AP-832\">AP-832</a>)."
"%%%  <h2><a name=\"functions\">Function Details</a></h2>"
"%%%"
"%%%  <h3 class=\"function\"><a name=\"parse-1\">parse/1</a></h3>"
"%%%  <div class=\"spec\">"
"%%%  <p><tt>parse(Tokens) -&gt; Result</tt>"
"%%%  <ul class=\"definitions\">"
"%%%    <li><tt>Tokens = [Token] </tt></li>"
"%%%    <li><tt>Token = {Category, LineNumber, Symbol}"
"%%% 			| {Symbol, LineNumber}</tt></li>"
"%%%    <li><tt>Category = string | number</tt></li>"
"%%%    <li><tt>Symbol = dot | exact | notexact | lt | lte"
"%%% 			| gt | gte | regex | like | notlike | in | notin"
"%%% 			| contains | notcontain | containsall</tt></li>"
"%%%    <li><tt>Result = {ok, Filters}"
"%% 			| {error, {LineNumber, Module, Message}}</tt></li>"
"%%%    <li><tt>Filters = term()</tt></li>"
"%%%    <li><tt>LineNumber = integer()</tt></li>"
"%%%    <li><tt>Module = atom()</tt></li>"
"%%%    <li><tt>Message = term()</tt></li>"
"%%%  </ul></p>"
"%%%  </div>"
"%%%  <p>Parse the input <tt>Tokens</tt> according to the grammar"
"%%%  of the advanced attribute filtering pattern.</p>"
"%%%"
.

Nonterminals filters filter collection complex field value.

Terminals '[' ']' '{' '}' dot number string exact notexact lt lte gt gte regex like notlike in notin contains notcontain containsall.

Rootsymbol filters.

Nonassoc 100 exact notexact lt lte gt gte regex like notlike in notin contains notcontain containsall.

filters -> filter :
	['$1'].
filters -> filter filters :
	['$1' | '$2'].
filters -> collection.
filters -> complex.

collection -> '[' filters ']'.
complex -> '{' filters'}'.

field -> string :
	element(3, '$1').
field -> string dot field :
	element(3, '$1') ++ "." ++ '$3'.

value -> string :
	element(3, '$1').
value -> number :
	element(3, '$1').

filter -> field exact value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field notexact value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field lt value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field lte value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field gt value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field gte value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field regex value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field like value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field notlike value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field in value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field notin value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field contains value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field notcontain value :
	{'$1', element(1, '$2'), '$3'}.
filter -> field containsall value :
	{'$1', element(1, '$2'), '$3'}.
