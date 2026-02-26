package main

import (
	"testing"
)

func TestParseProductRow(t *testing.T) {
	// Escenario 1: Parsing normal de categorías
	id, name, desc, pic, curr, cats := "1", "Botas", "De cuero", "bota.jpg", "USD", "ropa,calzado,invierno"
	var units int64 = 50
	var nanos int32 = 0

	product := parseProductRow(id, name, desc, pic, curr, cats, units, nanos)

	if len(product.Categories) != 3 {
		t.Errorf("Se esperaban 3 categorías, se obtuvieron %d", len(product.Categories))
	}
	if product.Categories[0] != "ropa" || product.Categories[2] != "invierno" {
		t.Errorf("Las categorías no se parsearon correctamente: %v", product.Categories)
	}
}

func TestParseProductRowEmptyCategories(t *testing.T) {
	// Escenario 2: Sin categorías
	product := parseProductRow("2", "Taza", "Cerámica", "taza.jpg", "USD", "", 10, 0)
	if len(product.Categories) != 0 {
		t.Error("Se esperaba una lista de categorías vacía")
	}
}

func TestMoneyParsing(t *testing.T) {
	// Escenario 3: Estructura de moneda
	product := parseProductRow("3", "PC", "Gamer", "pc.jpg", "EUR", "tech", 1200, 500)
	if product.PriceUsd.CurrencyCode != "EUR" || product.PriceUsd.Units != 1200 || product.PriceUsd.Nanos != 500 {
		t.Errorf("Error en el mapeo de precios: %v", product.PriceUsd)
	}
}