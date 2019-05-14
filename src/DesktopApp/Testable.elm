module DesktopApp.Testable exposing
    ( Effect(..)
    , File
    , JsonMapping
    , jsonFile
    , jsonMapping
    , program
    , staticString
    , with
    , withInt
    )

import DesktopApp.Ports as Ports
import Dict exposing (Dict)
import Html exposing (Html)
import Json.Decode exposing (Decoder)
import Json.Encode as Json


type Effect
    = WriteOut ( String, String )
    | LoadFile String


program :
    { init : ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> Html msg
    , files : File model msg
    , noOp : msg
    }
    ->
        { init : () -> ( model, ( Cmd msg, List Effect ) )
        , subscriptions : model -> Sub msg
        , update : msg -> model -> ( model, ( Cmd msg, List Effect ) )
        , view : model -> { body : List (Html msg), title : String }
        }
program config =
    let
        saveFiles ( model, cmd ) =
            ( model
            , ( cmd
              , [ config.files ]
                    |> List.map (\f -> encodeFile f model)
                    |> List.map WriteOut
              )
            )

        decoders =
            [ config.files ]
                |> List.map (\(File filename (JsonMapping _ decode)) -> ( filename, decode ))
                |> Dict.fromList
    in
    { init =
        \() ->
            let
                ( model, cmd ) =
                    config.init
            in
            ( model
            , ( cmd
              , [ config.files ]
                    |> List.map (\(File name _) -> name)
                    |> List.map LoadFile
              )
            )
    , update =
        \msg model ->
            config.update msg model
                |> saveFiles
    , subscriptions =
        let
            handleLoad ( filename, result ) =
                case result of
                    Nothing ->
                        config.noOp

                    Just body ->
                        case Dict.get filename decoders of
                            Nothing ->
                                -- Log error?
                                config.noOp

                            Just decoder ->
                                case Json.Decode.decodeString decoder body of
                                    Err err ->
                                        -- Log error?
                                        config.noOp

                                    Ok value ->
                                        value
        in
        \model ->
            Sub.batch
                [ config.subscriptions model
                , Ports.fileLoaded handleLoad
                ]
    , view =
        \model ->
            { title = ""
            , body =
                [ config.view model
                ]
            }
    }


type File model msg
    = File String (JsonMapping msg model)


encodeFile : File model msg -> model -> ( String, String )
encodeFile (File filename (JsonMapping fields _)) model =
    let
        json =
            Json.object
                (List.map (\( k, f ) -> ( k, f model )) fields)
    in
    ( filename, Json.encode 0 json )


jsonFile : String -> (b -> msg) -> JsonMapping b a -> File a msg
jsonFile filename toMsg (JsonMapping encode decode) =
    File filename (JsonMapping encode (Json.Decode.map toMsg decode))


type JsonMapping a b
    = JsonMapping (List ( String, b -> Json.Value )) (Decoder a)


jsonMapping : a -> JsonMapping a b
jsonMapping a =
    JsonMapping [] (Json.Decode.succeed a)


with : String -> (x -> a) -> (a -> Json.Value) -> Decoder a -> JsonMapping (a -> b) x -> JsonMapping b x
with name get toJson fd (JsonMapping fields decoder) =
    JsonMapping (( name, get >> toJson ) :: fields) (Json.Decode.map2 (\a f -> f a) (Json.Decode.field name fd) decoder)


withInt : String -> (x -> Int) -> JsonMapping (Int -> b) x -> JsonMapping b x
withInt name get =
    with name get Json.int Json.Decode.int


staticString : String -> String -> JsonMapping a x -> JsonMapping a x
staticString name value (JsonMapping fields decoder) =
    JsonMapping (( name, \_ -> Json.string value ) :: fields) decoder