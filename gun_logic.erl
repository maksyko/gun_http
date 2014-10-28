-module(gun_logic).
%% @doc Gun client for communicating an HTTP server
%% All data received from the server is sent to the controlling process as a message.
%% First a response message is sent, then zero or more data messages.
%% If something goes wrong, error messages are sent instead.
%% @end

-export([request/4]).
-export([gun_request/7]).

-type method()      :: post | get.
-type in_method()   :: Method   :: method().
-type in_url()      :: Url      :: string().
-type in_headers()  :: Headers  :: list().
-type in_body()     :: Body     :: <<>>.
-type in_port()     :: Port     :: integer().
-type out_request() :: {ok, {
  {
    HTTPVersion   :: string(),
    StatusCode    :: integer(),
    ReasonPhrase  :: string()
  },
  Headers :: list(), Body :: <<>>}}
| {error, Reason :: list()}.

%%--------------------------------------------------------------------------
%% request(Method, Url, Headers, Headers) ->
%%  {ok,{HTTPVersion, StatusCode, ReasonPhrase}, Headers, Body}
%%  | {error, Reason}
%%
%%	Method - atom() = get | post |
%%	Url - string()
%%	HTTPVersion = string()
%%	StatusCode = integer()
%%	ReasonPhrase = string()
%%	Headers = [Header]
%%      Header = {Field, Value}
%%	Field = string()
%%	Value = string()
%%	Body = binary()
%%--------------------------------------------------------------------------
-spec request(in_method(), in_url(), in_headers(), in_body()) ->
  out_request().

request(Method, Url, Headers, Body)
  when ((Method =:= post) orelse (Method =:= get)) andalso
  is_atom(Method) andalso
  is_list(Url) andalso
  is_list(Headers) andalso
  is_binary(Body) ->
  case http_uri:parse(Url) of
    {error, Reason} ->
      {error, {bad_format, Reason}};
    {ok, {_, _, ParseUrl, Port, ParseHeaders, ParseBody}} ->
      gun_request(Method, ParseUrl, Port, ParseHeaders, ParseBody, Headers, Body)
  end;
request(Method, Url, Headers, Body) ->
  {error, {bag_format, incoming_data, {Method, Url, Headers, Body}}}.

%%--------------------------------------------------------------------------
%% gun_request(Method, ParseUrl, Port, ParseHeaders, ParseBody, Options, Query) ->
%%  {ok,{HTTPVersion, StatusCode, ReasonPhrase}, Headers, Body}
%%  | {error, Reason}
%%
%%--------------------------------------------------------------------------
-spec gun_request(in_method(), in_url(), in_port(), in_headers(), in_body(), Options:: list(), Query:: list()) ->
  out_request().

gun_request(Method, ParseUrl, Port, ParseHeaders, ParseBody, Options, Query) ->

  {ok, Pid} = gun:open(ParseUrl, Port),
  StreamRef =
    case Method of
      post ->
        gun:Method(Pid, ParseHeaders ++ ParseBody, Options, Query);
      get ->
        gun:Method(Pid, ParseHeaders ++ ParseBody)
    end,
  receive
    {'DOWN', _, _, _, Reason} ->
      {error, {failde_connect, down, Reason}};
    {gun_response, Pid, StreamRef, fin, Status, Headers} ->
      {data, {Headers, Status, <<>>}};
    {gun_response, Pid, StreamRef, nofin, Status, Headers} ->
      case receive_data(Pid, StreamRef) of
        {error, NoData} ->
          {error, NoData};
        {data, Body} ->
          {ok, {{"HTTP/1.1", Status, "OK"}, Headers, Body}}
      end
  after 5000 ->
    gun:close(Pid),
    {error, failed_connect}
  end.

%%--------------------------------------------------------------------------
%% receive_data(Pid, StreamRef) -> {data, Data} | {error, Reason}
%%
%% Pid = pid()
%% StreamRef = reference
%%--------------------------------------------------------------------------

-spec receive_data(Pid::pid(), StreamRef::char()) ->
  {data, Data::<<>>} | {error, Reason::list()}.

receive_data(Pid, StreamRef) ->
  receive
    {'DOWN', _, _, _, Reason} ->
      {error, {down, Reason}};
    {gun_data, Pid, StreamRef, nofin, Data} ->
      {data, Data};
    {gun_data, Pid, StreamRef, fin, Data} ->
      {data, Data}
  after 5000 ->
    {error, failed_connect}
  end.