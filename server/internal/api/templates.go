package api

import (
	"encoding/json"
	"html/template"
	"io/fs"
	"net/http"
	"strings"
)

var funcMap = template.FuncMap{
	"lower": strings.ToLower,
	"title": strings.Title, //nolint:staticcheck
	"join":  strings.Join,
	"hasPrefix":  strings.HasPrefix,
	"trimPrefix": strings.TrimPrefix,
	"toJSON": func(v any) template.JS {
		b, err := json.Marshal(v)
		if err != nil {
			return template.JS("null")
		}
		return template.JS(b)
	},
}

func renderTemplate(webFS fs.FS, name string, w http.ResponseWriter, data any) error {
	tmpl, err := template.New(name).Funcs(funcMap).ParseFS(webFS, "templates/"+name)
	if err != nil {
		return err
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	return tmpl.Execute(w, data)
}
