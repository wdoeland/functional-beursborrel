module Admin exposing (Model (..), Msg (..), init, subscriptions, update, view, exit)

import Drink exposing (DrinkList, drinkListDecoder)
import Order exposing (OrderList)
import Session
import Element exposing (Element, text)
import Element.Input as Input
import Urls
import List exposing (map, filter, head)
import Time
import Maybe exposing (Maybe, withDefault)
import Http
import Json.Decode
import Json.Encode

type Msg
    = None
    | GotDrinks (Result Http.Error (DrinkList))
    | IncreaseOrder Int  -- The int is the id of the order
    | PlaceOrder
    | GotOrderPrice (Result Http.Error Float)
    | Update


type Model
    = Failure Session.Data (Maybe DrinkList) (Maybe OrderList)
    | Loading Session.Data (Maybe DrinkList) (Maybe OrderList)
    | Login Session.Data
    | ReceivedOrder Session.Data (Maybe DrinkList) Float
    | Order Session.Data DrinkList OrderList


init : Session.Data -> Maybe DrinkList -> (Model, Cmd Msg)
init data maybeDrinks =
    ( Loading data maybeDrinks Nothing
    , getDrinks
    )


exit : Model -> Session.Data
exit model =
    case model of
        Failure data _ _ ->
            data
            
        Loading data _ _ ->
            data
            
        Login data ->
            data
            
        ReceivedOrder data _ _ ->
            data            

        Order data _ _ ->
            data


exitDrinks : Model -> Maybe DrinkList
exitDrinks model = 
    case model of
        Failure _ maybeDrinks _ ->
            maybeDrinks
        
        Loading _ maybeDrinks _ ->
            maybeDrinks

        ReceivedOrder _ maybeDrinks _ ->
            maybeDrinks

        Order _ drinks _ ->
            Just drinks

        _ ->
            Nothing


exitOrders : Model -> Maybe OrderList
exitOrders model =
    case model of
        Failure _ _ maybeOrders ->
            maybeOrders

        Loading _ _ maybeOrders ->
            maybeOrders

        Order _ _ orders ->
            Just orders

        _ ->
            Nothing


view : Model -> (String, List (Element Msg))
view model =
    case model of
        Order _ drinks order ->
            ( "Order"
            , [ renderOrders drinks order
              , Input.button [] { onPress = Just PlaceOrder, label = text "Place order" }
              , Input.button [] { onPress = Just Update, label = text "Update prices" } 
              ]
            )

        ReceivedOrder _ _ price ->
            ( "Received Order"
            , [ text <| "Order placed, price = $" ++ String.fromFloat price
              , Input.button [] { onPress = Just Update, label = text "New order" }
              ]
            )

        _ ->
            ( "Error"
            , [ text "Updating prices failed!"
              , Input.button [] { onPress = Just Update, label = text "Retry" } 
              ] 
            )


totalPrice : List (Order.Data, String, Float) -> Float
totalPrice orders =
    List.foldl (\(order, _, price) -> (+) (toFloat order.amount * price)) 0 orders


renderOrders : DrinkList -> OrderList -> Element Msg
renderOrders drinks orders =
    let
        mappedDrinkOrders =
            mapDrinkOrder drinks orders
    in
    Element.column [] (List.map renderOrder mappedDrinkOrders ++ [text ("Total = $" ++ String.fromFloat (totalPrice mappedDrinkOrders))])


renderOrder : (Order.Data, String, Float) -> Element Msg
renderOrder (order, name, price) =
    Input.button [] { onPress = Just <| IncreaseOrder order.id, label =  text <| String.fromInt order.amount ++ " times " ++ name ++ " $" ++ String.fromFloat price ++ " = " ++ String.fromFloat (toFloat order.amount * price) }

mapDrinkOrder : DrinkList -> OrderList -> List (Order.Data, String, Float)
mapDrinkOrder drinks orders =
    map (\drink -> (withDefault { id = drink.id, amount = 0} <| findOrder drink orders.drinks, drink.name, drink.price)) drinks
    

findOrder : Drink.Data -> List Order.Data -> Maybe Order.Data
findOrder drink orders =
    head <| filter (\order -> order.id == drink.id) orders


subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every (10 * 1000) <| always Update


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        GotDrinks result ->
            case result of
                Ok drinks ->
                    let
                        orders =
                            withDefault (Order.new <| map (\drink -> (drink.id, 0)) drinks) (exitOrders model)
                    in
                    (Order (exit model) drinks orders, Cmd.none)
                
                Err _ ->
                    (Failure (exit model) (exitDrinks model) (exitOrders model), Cmd.none)

        IncreaseOrder id ->
            case model of
                Order _ drinks orders ->
                    (Order (exit model) drinks <| increaseOrder id orders, Cmd.none)
                
                Loading _ drinks orders ->
                    (Loading (exit model) drinks <| Maybe.map (increaseOrder id) orders, Cmd.none)

                Failure _ drinks orders ->
                    (Failure (exit model) drinks <| Maybe.map (increaseOrder id) orders, Cmd.none)

                _ ->
                    (model, Cmd.none)

        Update ->
            (model, getDrinks)

        PlaceOrder ->
            case exitOrders model of
                Just orders ->
                    (model, placeOrder orders)
                
                Nothing ->
                    (model, Cmd.none)

        GotOrderPrice result ->
            case result of
                Ok price ->
                    (ReceivedOrder (exit model) (exitDrinks model) price, Cmd.none)
                
                Err _ ->
                    (Failure (exit model) (exitDrinks model) (exitOrders model), Cmd.none)

        _ ->
            (model, Cmd.none)


placeOrder : OrderList -> Cmd Msg
placeOrder orders =
    Http.post
        { url = Urls.orderUrl
        , body = Http.jsonBody <| Json.Encode.object [("drinks", 
            Json.Encode.list (\order -> Json.Encode.object [("id", Json.Encode.int order.id),  ("amount", Json.Encode.int order.amount)]) orders.drinks  
          )]
        , expect = Http.expectJson GotOrderPrice <| Json.Decode.field "price" Json.Decode.float
        }


getDrinks : Cmd Msg
getDrinks =
    Http.get
        { url = Urls.drinkUrl
        , expect = Http.expectJson GotDrinks drinkListDecoder 
        }


increaseOrder : Int -> OrderList -> OrderList
increaseOrder id orders =
    { drinks = map (\order -> if order.id == id then { id = order.id, amount = order.amount + 1} else order) orders.drinks }