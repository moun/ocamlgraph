
open Graph
open Ed_hyper

type visibility = Visible | BorderNode | Hidden

type mode = Normal | Selected | Focused | Selected_Focused

type node_info = 
    { 
      label : string;
      mutable visible : visibility;
      mutable depth : int;
      mutable vertex_mode : mode;
      mutable turtle : turtle;
    }
      
let make_node_info s = 
  { 
    label = s; 
    visible = Hidden; 
    depth = 0; 
    vertex_mode = Normal; 
    turtle = dummy_turtle 
  }

type edge_info = 
    {
      mutable visited : bool;
      mutable edge_mode : mode;
      mutable edge_turtle : turtle;
      mutable edge_distance : float;
      mutable edge_steps : int;
    }
      
let make_edge_info () =
  { 
    visited = false; 
    edge_mode = Normal;
    edge_turtle = dummy_turtle; 
    edge_distance = 0.; 
    edge_steps = 0; 
  }

module EDGE = struct
  type t = edge_info
  let compare = Pervasives.compare
  let default = make_edge_info ()
end

module G = 
  Imperative.Graph.AbstractLabeled(struct type t = node_info end)(EDGE)

module B = Builder.I(G)

module GmlParser = 
  Gml.Parse
    (B)
    (struct 
      let node l = 
	make_node_info
	  (try 
	      match List.assoc "id" l 
	      with Gml.Int n -> string_of_int n | _ -> "<no id>"
	    with Not_found -> "<no id>")
      let edge _ = make_edge_info ()
    end)


(*module GmlPrinter =
  Gml.Print
    (G)
    ( ?? )*)

module DotParser = 
  Dot.Parse
    (B)
    (struct 
      let node (id,_) _ = match id with
	| Dot_ast.Ident s
	| Dot_ast.Number s
	| Dot_ast.String s
	| Dot_ast.Html s -> make_node_info s
      let edge _ = make_edge_info ()
    end)

let parse_file f = 
  if Filename.check_suffix f ".gml" then
    GmlParser.parse f
  else
    DotParser.parse f

module Components = Components.Make(G)
module Dfs = Traverse.Dfs(G)

(* current graph *)

let graph = ref (G.create ())

exception Choose of G.V.t

let choose_root () =
  try
    G.iter_vertex (fun v -> raise (Choose v)) !graph;
    Format.eprintf "empty graph@.";exit 0
  with Choose v ->
    v

let string_of_label x = (G.V.label x).label

let edge v w = G.mem_edge !graph v w || G.mem_edge !graph w v 


(* Parsing of the command line *)
let load_graph f =
  graph := parse_file f

let dfs = ref false

let refresh_rate = ref 10

let aa = ref true

let () = 
  Arg.parse
    ["-dfs", Arg.Set dfs, "DFS drawing strategy";
     "-bfs", Arg.Clear dfs, "BFS drawing strategy";
     "-rr", Arg.Set_int refresh_rate, "set the refresh rate, must be greater than 0";
     "-aa", Arg.Clear aa, "turn off anti-aliased mode";
    ]
    load_graph 
    "editor [options] <graph file>"

    
(* successor edges *)

module H2 = 
  Hashtbl.Make
    (struct 
      type t = G.V.t * G.V.t
      let hash (v,w) = Hashtbl.hash (G.V.hash v, G.V.hash w)
      let equal (v1,w1) (v2,w2) = G.V.equal v1 v2 && G.V.equal w1 w2 
    end)



module H = Hashtbl.Make(G.V)


(*  vertex select and unselect *)

(* a counter for selected vertices *)
let nb_selected = ref 0

(* a belonging test to selection *)
let is_selected (x:G.V.t) = 
  let mode =(G.V.label x).vertex_mode in
  mode = Selected ||
  mode = Selected_Focused

let selected_list () =
  let vertex_selection =ref [] in
  G.iter_vertex (fun v -> if (is_selected v) then vertex_selection :=v::(!vertex_selection)) !graph;
  let compare s1 s2 = String.compare (string_of_label s1) (string_of_label s2) in
  List.sort compare !vertex_selection
  



type ed_event = Select | Unselect | Focus | Unfocus

let update_vertex vertex event =
  let vertex_info = G.V.label vertex in
  begin
    match vertex_info.vertex_mode, event with
      | Normal, Select -> vertex_info.vertex_mode <- Selected; incr nb_selected
      | Normal, Focus -> vertex_info.vertex_mode <- Focused
      | Normal, _ -> ()
      | Selected, Focus -> vertex_info.vertex_mode <- Selected_Focused
      | Selected, Unselect -> vertex_info.vertex_mode <- Normal; decr nb_selected
      | Selected, _ -> ()
      | Focused, Select -> vertex_info.vertex_mode <- Selected_Focused; incr nb_selected
      | Focused, Unfocus -> vertex_info.vertex_mode <- Normal
      | Focused, _ -> ()
      | Selected_Focused, Unselect -> vertex_info.vertex_mode <- Focused; decr nb_selected
      | Selected_Focused, Unfocus -> vertex_info.vertex_mode <- Selected
      | Selected_Focused, _ -> ()
  end;
  G.iter_succ_e
    ( fun edge ->
	let edge_info = G.E.label edge in
	let dest_vertex = G.E.dst edge in 
	begin match  edge_info.edge_mode, event with
	  | Normal, Select -> edge_info.edge_mode <- Selected
	  | Normal, Focus -> edge_info.edge_mode <- Focused
	  | Normal, _ -> ()
	  | Selected, Focus -> edge_info.edge_mode <- Selected_Focused
	  | Selected, Unselect -> if not(is_selected dest_vertex) then edge_info.edge_mode <- Normal
	  | Selected, _ -> ()
	  | Focused, Select -> edge_info.edge_mode <- Selected_Focused
	  | Focused, Unfocus -> edge_info.edge_mode <- Normal
	  | Focused, _ -> ()
	  | Selected_Focused, Unselect -> if not(is_selected dest_vertex) then edge_info.edge_mode <- Focused
	  | Selected_Focused, Unfocus -> edge_info.edge_mode <- Selected
	  | Selected_Focused, _ -> ()
	end;		   
    ) !graph vertex
      


(* to select and unselect all vertices *)

let select_all () =  
  G.iter_vertex (fun v -> 
		   if not(is_selected v) 
		   then begin 
		     let v = G.V.label v in
		     v.vertex_mode <- Selected;
		     incr nb_selected 
		   end
		) !graph;
  G.iter_edges_e (fun e -> let e = G.E.label e in e.edge_mode <- Selected) !graph


let unselect_all () =  
  G.iter_vertex (fun v -> 
		   if (is_selected v)
		   then begin 
		     let l = G.V.label v in
		     l.vertex_mode <- Normal;
		     decr nb_selected 
		   end
		) !graph;
  G.iter_edges_e (fun e -> let e = G.E.label e in e.edge_mode <- Normal) !graph

