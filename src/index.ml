open Batteries

type t

type kv =
  | Double of (string * float)
  | Long of (string * int)
  | String of (string * string)

external from_file : string -> string -> t = "ml_grib_index_new_from_file"

let of_file filename keys =
  let keys = String.concat "," keys in
  from_file filename keys

external delete : t -> unit = "ml_grib_index_delete"

external select_double : t -> string -> float -> unit = "ml_grib_index_select_double"
external select_long : t -> string -> int -> unit = "ml_grib_index_select_long"
external select_string : t -> string -> string -> unit = "ml_grib_index_select_string"

external size : t -> string -> int = "ml_grib_index_get_size"

external next_handle : t -> Handle.t option = "ml_grib_handle_new_from_index"

external write : t -> string -> unit = "ml_grib_index_write"
external read : string -> t = "ml_grib_index_read"

let double_key k v = Double (k, v)
let long_key k v = Long (k, v)
let string_key k v = String (k, v)

let float_key = double_key
let int_key = long_key

let select index kv =
  match kv with
  | Double (k, d) -> select_double index k d
  | Long (k, l) -> select_long index k l
  | String (k, s) -> select_string index k s

let keys_of_kvs l =
  List.map (
    fun kv ->
      match kv with
      | Double (k, _)
      | Long (k, _)
      | String (k, _) -> k
  ) l

let apply_kvs index l =
  List.iter (select index) l

(** Iterate [f] over each handle included in [t]. *)
let iter f t =
  let continue = ref true in
  while !continue do
    match next_handle t with
    | Some handle ->
        with_dispose ~dispose:Handle.delete f handle
    | None ->
        (* Break out of the loop when we are out of handles *)
        continue := false;
  done;
  ()

(** Apply [f] to each handle included in [t]. *)
let map f t =
  let rec inner l =
    match next_handle t with
    | Some handle ->
        let result = with_dispose ~dispose:Handle.delete f handle in
        inner (result :: l)
    | None -> List.rev l
  in
  inner []

(** Apply [f] on the index from [filename], optionally initializing the index
    with the (key, value) pairs from [init]. *)
let with_file_in ?init filename keys f =
  with_dispose ~dispose:delete (
    fun index ->
      Option.may (apply_kvs index) init;
      f index
  ) (of_file filename keys)

(** Like [iter], but starting with a file *)
let iter_file f filename init =
  let keys = keys_of_kvs init in
  with_file_in ~init filename keys (iter f)

(** Like [map]. but starting with a file *)
let map_file f filename init =
  let keys = keys_of_kvs init in
  with_file_in ~init filename keys (map f)

(** [get index kvs f] applies [f] to the handle matched by [kvs] in [index]. *)
let get index kvs f =
  apply_kvs index kvs;
  let matching_fields = map f index in
  match matching_fields with
  | [] -> None
  | hd :: [] -> Some hd
  | _ -> invalid_arg "Multiple results from GRIB index"

(** [get_exn index kvs f] is like {!get} but raises an exception rather than
    returning [None].

    @raise Not_found if no messages matching [kvs] are in [index]. *)
let get_exn index kvs f =
  match get index kvs f with
  | Some x -> x
  | None -> raise Not_found
