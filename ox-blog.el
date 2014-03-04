;;; ox-blog.el --- Blog Back-End for Org Export Engine

;; Copyright (C) 2013, 2014  Robert Klein

;; Author: Robert Klein <roklein at roklein dot de>
;; Keywords: WordPress, HTML

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This library implements an blog back-end for the Org
;; generic exporter.

;; To test it, run:
;;
;;   M-x org-blog-export-as-html
;;
;; in an Org mode buffer.  See ox.el and ox-html.el for more details
;; on how this exporter works.

;;; Code:
(require 'ox-html)  ;; in turn requires ox-publish and ox.
(require 'xml-rpc)
; (require 'wp-xml-rpc)
; (require 'cl)

(org-export-define-derived-backend 'blog 'html
  :menu-entry
  '(?b "Export to WP Blog Presentation"
       ((?H "To temporary buffer" org-blog-export-as-html)
	(?h "To file" org-blog-export-to-html)
        (?d "To blog as draft" org-blog-export-to-blog-as-draft)
        (?p "To blog and publish" org-blog-export-to-blog-as-publish)
	(?o "To file and open"
	    (lambda (a s v b)
	      (if a (org-blog-export-to-html t s v b)
		(org-open-file (org-blog-export-to-html nil s v b)))))))
  :options-alist
  '((:blog-url "BLOG_URL" nil nil t)
    (:blog-username "BLOG_USERNAME" nil nil t)
    (:blog-id "BLOG_ID" nil nil t)
    (:blog-password "BLOG_PASSWORD" nil nil t)
    (:blog-post-id "BLOG_POST_ID" nil nil t)
    (:blog-publish-datetime "BLOG_PUBLISH_DATETIME" nil nil t)
    (:blog-post-type "BLOG_POST_TYPE" "post-type" org-blog-post-type t)
    (:blog-syntax-highlighter "BLOG_SYNTAX_HIGHLIGHTER" "bloghl"
                              org-blog-syntax-highlighter t)
    (:blog-timezone "BLOG_TIMEZONE" "blogtz" nil t)
    (:blog-tags "BLOG_TAGS" nil org-blog-tags newline)
    (:blog-confirm-new-tags "BLOG_CONFIRM_NEW_TAGS" nil
                            org-blog-confirm-new-tags t)
    (:blog-categories "BLOG_CATEGORIES" nil org-blog-categories newline)
    (:blog-confirm-new-categories "BLOG_CONFIRM_NEW_CATEGORIES"
                                  nil org-blog-confirm-new-categories t)
    (:blog-use-tags-as-categories "BLOG_USE_TAGS_AS_CATEGORIES" nil nil t)
    (:blog-upload-filetypes "BLOG_UPLOAD_FILETYPES" nil org-blog-upload-filetypes split))
  :translate-alist
  '(;(inner-template . org-blog-inner-template) ;; use org-html-inner-template
    (keyword . org-blog-keyword)
    (latex-environment . org-blog-latex-environment)
    (latex-fragment . org-blog-latex-fragment)
    (link . org-blog-link)
    (src-block . org-blog-src-block)
    (template . org-blog-template)))



;;; Internal variables

;(defvar org-blog-id 1
;  "ID of blog.  Typically 1.")


(defvar org-blog-files-to-upload nil
  "A list containing the file names to upload to the blog.")


(defvar org-blog-image-list nil
  "Images to upload/change URL in buffer.")


;;; User Configuration Variables

(defgroup org-export-blog nil
  "Options for exporting Org mode files to a wordpress based blog."
  :tag "Org Export Blog"
  :group 'org-export)

(defcustom org-blog-project-alist nil
  "Association list to control blog publication behavior.
Eash element of the alist is a blog 'project.'  The CAR of each
element is a string, uniquely identifying the project.  The CDR
of each element is in the following form:

1. A well-formed property list with an even number of elements,
   alternating keys and values, specifying parameters for the
   publishing process.

When a property is given a value in `org-blog-project-alist',
its setting overrides the value of the corresponding user
variable (if any) during publishing.  However, options set within
a file override everything.

Most properties are optional, but some should always be set:

  `:base-directory'

    Directory containing publishing source files.

  `:blog-url'

    Blog where posts will be published.

  `:blog-id'

    Blog ID; usually `1'.

Some properties control details of the Org publishing process,
and are equivalent to the corresponding user variables listed in
the right column.  Back-end specific properties may also be
included.  See the back-end documentation for more information.

  :user-name              `org-blog-username'
  :syntax-highlighter     `org-blog-syntax-highlighter'
  :tags                   `org-blog-tags'
  :confirm-new-tags       `org-blog-confirm-new-tags'
  :categories             `org-blog-categories'
  :confirm-new-categories `org-blog0confirm-new-categories'
  :upload-filetypes       `org-blog-upload-filetypes'"
  :group 'org-export-blog
  :type 'alist)




(defcustom org-blog-post-type "post"
  "Post yype of blog post (post/page).
Defaults to \"post\"."
  :group 'org-export-blog
  :type '(choice
          (const :tag "Post" "post")
          (const :tag "Page" "page")))

(defcustom org-blog-syntax-highlighter "org-mode"
  "Syntax highlighter to be used.
Defaults to \"org-mode\"."
  :group 'org-export-blog
  :type '(choice
          (const :tag "org-mode" "org-mode")
          (const :tag "WP-Syntax" "wp-syntax")
          (const :tag "Alex Gorbatchev's SyntaxHighlighter" "syntaxhighlighter")
          (const :tag "wordpress.com SyntaxHighlighter" "wordpress.com")))


(defcustom org-blog-tags ""
  "Tags for the blog post."
  :group 'org-export-blog
  :type 'string)

(defcustom org-blog-confirm-new-tags nil
  "When non-nil new tags must be confirmed by the user."
  :group 'org-export-blog
  :type 'boolean)

(defcustom org-blog-categories ""
  "Categories for the blog post."
  :group 'org-export-blog
  :type 'string)

(defcustom org-blog-confirm-new-categories t
  "When non-nil new categories must be confirmed by the user."
  :group 'org-export-blog
  :type 'boolean)

(defcustom org-blog-upload-filetypes '("jpg" "jpeg" "png" "gif"
                                       "pdf" "doc" "docx" "odt"
                                       "xls" "xslx"
                                       "ppt" "pptx" "pps" "ppsx"
                                       "mp3" "m4a" "ogg" "wav"
                                       "mp4" "m4v" "mov" "wmv" "avi"
                                       "mpg" "ogv" "3gp" "3g2")
  "file types to upload to blog when linked via file://"
  :group 'org-export-blog
  :type 'list)


(defconst org-blog-syntax-highlighter-alist
 ; "
 ; 
 ;   - beginning-of-tag, e.g. '<'
 ;   - ending of tag, e.g. '>'
 ;   - tag, e.g. 'pre'
 ;   - tag end marker, e.g. '/'
 ;   - keyword for language, e.g. 'class' (for <pre class=...)
 ;   - default class, if no language defined
 ;   - list of supported highlighter language identifiers
 ;     (for org-mode a list of major emacs mode languages; they'll
 ;      be colorized w/ htmlize.el )
 ;   - alist mapping of org-babel language identifier and
 ;     highlighter language identifier
 ; 
 ;"
  '(("org-mode" .
     ("<" ">" "pre" "/" "class" "example"
      (list "asymptote" "awk" "C" "cpp" "calc" "clojure" "css" "ditaa" "dot"
            "emacs-lisp" "euklides" "formus" "F90" "gnuplot" "haskell" "java"
            "js" "latex" "ledger" "ly" "lisp" "makefile" "mathomatic" "matlab" "max"
            "mscgen" "ocaml" "octave" "org" "oz" "perl" "picolisp" "plantuml"
            "python" "R" "ruby" "sass" "scheme" "shen" "sh" "sql" "sqlite"
            "tcl"
            ;; above are the official babel and babel contrib languages
            ;; below are more names of emacs langeage-modes which can be edited
            ;; in latex src blocks, but not executed.
            "html" "nxhtml" "nxml")
      (list ("text" . "example"))
     nil nil nil nil nil))
    ("syntaxhighlighter" .
     ("[" "]" "sourcecode" "/" "language"
       "text"
       (list "actionscript3" "as3"
             "applescript"
             "bash" "shell"
             "c#" "c-sharp" "csharp"
             "coldfusion""cf"
             "cpp" "c"
             "css"
             "delphi" "pascal" "pas"
             "diff" "patch"
             "erl" "erlang"
             "groovy"
             "js" "jscript" "javascript"
             "java"
             "jfx" "javafx"
             "perl" "Perl" "pl"
             "php"
             "text" "plain"
             "powershell" "ps"
             "py" "python"
             "ruby" "rails" "ror" "rb"
             "sass" "scss"
             "scala"
             "sql"
             "vb" "vbnet"
             "xml" "xhtml" "xslt" "html")
       (list ("C" . "c")
             ("R" . "r")
             ("emacs-lisp" . "lisp")
             ("elisp" . "lisp")
             ("sh" . "bash"))
       "" "gutter=\"false\"" "firstline" "highlight" "title"))
    ("wordpress.com" .
     ("[" "]" "code" "/" "language"
       "text"
       (list "actionscript3" "bash" "clojure" "coldfusion" "cpp" "csharp"
             "css" "delphi" "erlang" "fsharp" "diff" "groovy" "html"
             "javascript" "java" "javafx" "matlab" "objc" "perl" "php"
             "text" "powershell" "python" "r" "ruby" "scala" "sql" "vb"
             "xml")
       (list ("R" . "r")
             ("emacs-lisp" . "lisp")
             ("elisp" . "lisp")
             ("sh" . "bash"))
       "" "gutter=\"false\"" "firstline" "highlight" "title"))
    ("wp-syntax" . 
     ("<" ">" "pre" "/" "lang"
       "text"
       (list "4cs" "6502acme" "6502kickass" "6502tasm" "68000devpac" "abap"
             "actionscript3" "actionscript" "ada" "algol68" "apache"
             "applescript" "apt_sources" "arm" "asm" "asp" "asymptote"
             "autoconf" "autohotkey" "autoit" "avisynth" "awk" "bascomavr"
             "bash" "basic4gl" "bf" "bibtex" "blitzbasic" "bnf" "boo"
             "caddcl" "cadlisp" "cfdg" "cfm" "chaiscript" "cil"
             "c_loadrunner" "clojure" "c_mac" "cmake" "cobol" "coffeescript"
             "c" "cpp" "cpp-qt" "csharp" "css" "cuesheet" "dcl" "dcpu16"
             "dcs" "delphi" "diff" "div" "dos" "dot" "d" "ecmascript"
             "eiffel" "email" "epc" "e" "erlang" "euphoria" "f1" "falcon"
             "fo" "fortran" "freebasic" "freeswitch" "fsharp" "gambas" "gdb"
             "genero" "genie" "gettext" "glsl" "gml" "gnuplot" "go" "groovy"
             "gwbasic" "haskell" "haxe" "hicest" "hq9plus" "html4strict"
             "html5" "icon" "idl" "ini" "inno" "intercal" "io" "java5"
             "java" "javascript" "j" "jquery" "kixtart" "klonec" "klonecpp"
             "latex" "lb" "ldif" "lisp" "llvm" "locobasic" "logtalk"
             "lolcode" "lotusformulas" "lotusscript" "lscript" "lsl2" "lua"
             "m68k" "magiksf" "make" "mapbasic" "matlab" "mirc" "mmix"
             "modula2" "modula3" "mpasm" "mxml" "mysql" "nagios" "netrexx"
             "newlisp" "nsis" "oberon2" "objc" "objeck" "ocaml-brief"
             "ocaml" "octave" "oobas" "oorexx" "oracle11" "oracle8"
             "oxygene" "oz" "parasail" "parigp" "pascal" "pcre" "perl6"
             "perl" "per" "pf" "php-brief" "php" "pic16" "pike"
             "pixelbender" "pli" "plsql" "postgresql" "povray"
             "powerbuilder" "powershell" "proftpd" "progress" "prolog"
             "properties" "providex" "purebasic" "pycon" "pys60" "python"
             "qbasic" "q" "rails" "rebol" "reg" "rexx" "robots" "rpmspec"
             "rsplus" "ruby" "sas" "scala" "scheme" "scilab" "sdlbasic"
             "smalltalk" "smarty" "spark" "sparql" "sql" "stonescript"
             "systemverilog" "tcl" "teraterm" "text" "thinbasic" "tsql"
             "typoscript" "unicon" "upc" "urbi" "uscript" "vala" "vbnet"
             "vb" "vedit" "verilog" "vhdl" "vim" "visualfoxpro"
             "visualprolog" "whitespace" "whois" "winbatch" "xbasic" "xml"
             "xorg_conf" "xpp" "yaml" "z80" "zxbasic")
       (list ("emacs-lisp" . "lisp")
             ("elisp" . "lisp")
             ("sh" . "bash"))
       "line=\"1\"" "" "line" "highlight" "src"))))

;; e.g.
;;(nth 1 (cdr (assoc "syntaxhighlighter" org-blog-syntax-highlighter-alist)))
;;(nth 2 (cdr (assoc "syntaxhighlighter" org-blog-syntax-highlighter-alist)))
;;(nth 3 (cdr (assoc "syntaxhighlighter" org-blog-syntax-highlighter-alist)))
;;(nth 4 (cdr (assoc "syntaxhighlighter" org-blog-syntax-highlighter-alist)))
;;(nth 5 (cdr (assoc "syntaxhighlighter" org-blog-syntax-highlighter-alist)))
;;(nth 6 (cdr (assoc "syntaxhighlighter" org-blog-syntax-highlighter-alist)))
;;(nth 7 (cdr (assoc "syntaxhighlighter" org-blog-syntax-highlighter-alist)))
;;(cdr (assoc "emacs-lisp" (nth 8 (cdr (assoc "syntaxhighlighter" org-blog-syntax-highlighter-alist)))))
;;;; nth > anzahl der elemente = nil
;;(nth 10 (cdr (assoc "syntaxhighlighter" org-blog-syntax-highlighter-alist)))




;;; Internal Functions
(defun org-blog--format-image (source attributes info)
  "Return \"img\" tag with given SOURCE and ATTRIBUTES.
SOURCE is a string specifying the location of the image.
ATTRIBUTES is a plist, as returned by
`org-export-read-attribute'.  INFO is a plist used as
a communication channel."
  ;; #+CAPTION: support (see
  ;;            http://codex.wordpress.org/Wrapping_Text_Around_Images)
  (message "attributes in format-image: %s" attributes)
  (cdar
   (add-to-list
    'org-blog-image-list
    `(,source
      .
      ,(org-html-close-tag
        "img"
        (org-html--make-attribute-string
         ;; attributes first, because we want the style to
         ;; be added without the quotes.
         (org-combine-plists
          attributes
          (let ((tmplist
                 (list :src source
                       :alt (if (string-match-p "^ltxpng/" source)
                                (org-html-encode-plain-text
                                 (org-find-text-property-in-string
                                  'org-latex-src
                                  source))
                              (file-name-nondirectory source))))
                (align  (org-element-interpret-data (plist-get attributes :align)))
                (style  (org-element-interpret-data (plist-get attributes :style))))
            (when (not (string= "" align))
              (add-to-list 'tmplist (concat "align" align))
              (add-to-list 'tmplist :class)
              ;; add ``empty'' :align, so it doesn't show in the export
              (add-to-list 'tmplist nil)
              (add-to-list 'tmplist :align))
            (when (not (string= "" style))
              (add-to-list 'tmplist
                           (progn
                             (when (string= (substring style 0 1) "\"")
                               (setq style (substring style 1)))
                             (when (string= (substring style -1) "\"")
                               (setq style (substring style 0 -1)))
                             style))
              (add-to-list 'tmplist :style))
            tmplist)))
        info)))))


;;; Transcode Functions

;;;; Latex Environment

(defun org-blog-latex-environment (latex-environment contents info)
  "Transcode a LATEX-ENVIRONMENT element from Org to HTML.
CONTENTS is nil.  INFO is a plist holding contextual information."
  (let ((processing-type (plist-get info :with-latex))
	(latex-frag (org-remove-indentation
		     (org-element-property :value latex-environment)))
	(attributes (org-combine-plists
                     (org-export-read-attribute :attr_html latex-environment)
                     (org-export-read-attribute :attr_blog latex-environment))))
    (case processing-type
      ((t mathjax)
       (org-html-format-latex latex-frag 'mathjax info))
      ((dvipng imagemagick)
       (let ((formula-link
	      (org-html-format-latex latex-frag processing-type info)))
	 (when (and formula-link (string-match "file:\\([^]]*\\)" formula-link))
	   ;; Do not provide a caption or a name to be consistent with
	   ;; `mathjax' handling.
	   (org-html--wrap-image
	    (org-blog--format-image
	     (match-string 1 formula-link) attributes info) info))))
      (t latex-frag))))


;;;; Latex Fragment

(defun org-blog-latex-fragment (latex-fragment contents info)
  "Transcode a LATEX-FRAGMENT object from Org to HTML.
CONTENTS is nil.  INFO is a plist holding contextual information."
  (let ((latex-frag (org-element-property :value latex-fragment))
	(processing-type (plist-get info :with-latex)))
    (case processing-type
      ((t mathjax)
       (org-html-format-latex latex-frag 'mathjax info))
      ((dvipng imagemagick)
       (let ((formula-link
	      (org-html-format-latex latex-frag processing-type info)))
	 (when (and formula-link (string-match "file:\\([^]]*\\)" formula-link))
	   (org-blog--format-image (match-string 1 formula-link) nil info))))
      (t latex-frag))))

;;;; Link

(defun org-blog-link (link desc info)
  "Transcode a LINK object from Org to HTML.

DESC is the description part of the link, or the empty string.
INFO is a plist holding contextual information.  See
`org-export-data'."
  (let* ((home (when (plist-get info :html-link-home)
		 (org-trim (plist-get info :html-link-home))))
	 (use-abs-url (plist-get info :html-link-use-abs-url))
	 (link-org-files-as-html-maybe
	  (function
	   (lambda (raw-path info)
	     "Treat links to `file.org' as links to `file.html', if needed.
           See `org-html-link-org-files-as-html'."
	     (cond
	      ((and org-html-link-org-files-as-html
		    (string= ".org"
			     (downcase (file-name-extension raw-path "."))))
	       (concat (file-name-sans-extension raw-path) "."
		       (plist-get info :html-extension)))
	      (t raw-path)))))
	 (type (org-element-property :type link))
	 (raw-path (org-element-property :path link))
	 ;; Ensure DESC really exists, or set it to nil.
	 (desc (org-string-nw-p desc))
	 (path
	  (cond
	   ((member type '("http" "https" "ftp" "mailto"))
	    (concat type ":" raw-path))
	   ((string= type "file")
	    ;; Links to ".org" files are just that in 'blog export,
	    ;; so we do not set the raw-path to a .html link.
            ;;
	    ;; If file path is absolute, prepend it with protocol
	    ;; component - "file://".
	    (cond ((file-name-absolute-p raw-path)
		   (setq raw-path
			 (concat "file://" (expand-file-name
					    raw-path))))
		  ((and home use-abs-url)
		   (setq raw-path (concat (file-name-as-directory home) raw-path))))
	    ;; Add search option, if any.  A search option can be
	    ;; relative to a custom-id or a headline title.  Any other
	    ;; option is ignored.
	    (let ((option (org-element-property :search-option link)))
	      (cond ((not option) raw-path)
		    ((eq (aref option 0) ?#) (concat raw-path option))
		    ;; External fuzzy link: try to resolve it if path
		    ;; belongs to current project, if any.
		    ((eq (aref option 0) ?*)
		     (concat
		      raw-path
		      (let ((numbers
			     (org-publish-resolve-external-fuzzy-link
			      (org-element-property :path link) option)))
			(and numbers (concat "#sec-"
					     (mapconcat 'number-to-string
							numbers "-"))))))
		    (t raw-path))))
	   (t raw-path)))
	 ;; Extract attributes from parent's paragraph.  HACK: Only do
	 ;; this for the first link in parent (inner image link for
	 ;; inline images).  This is needed as long as attributes
	 ;; cannot be set on a per link basis.
	 (attributes-plist
	  (let* ((parent (org-export-get-parent-element link))
		 (link (let ((container (org-export-get-parent link)))
			 (if (and (eq (org-element-type container) 'link)
				  (org-html-inline-image-p link info))
			     container
			   link))))
	    (and (eq (org-element-map parent 'link 'identity info t) link)
		 (org-combine-plists
                     (org-export-read-attribute :attr_html parent)
                     (org-export-read-attribute :attr_blog parent)))))
	 (attributes
	  (let ((attr (org-html--make-attribute-string attributes-plist)))
	    (if (org-string-nw-p attr) (concat " " attr) "")))
	 protocol)
    (cond
     ;; Image file.
     ((and org-html-inline-images
	   (org-export-inline-image-p link org-html-inline-image-rules))
      (org-blog--format-image path attributes-plist info))
     ;; Radio target: Transcode target's contents and use them as
     ;; link's description.
     ((string= type "radio")
      (let ((destination (org-export-resolve-radio-link link info)))
	(when destination
	  (format "<a href=\"#%s\"%s>%s</a>"
		  (org-export-solidify-link-text path)
		  attributes
		  (org-export-data (org-element-contents destination) info)))))
     ;; Links pointing to a headline: Find destination and build
     ;; appropriate referencing command.
     ((member type '("custom-id" "fuzzy" "id"))
      (let ((destination (if (string= type "fuzzy")
			     (org-export-resolve-fuzzy-link link info)
			   (org-export-resolve-id-link link info))))
	(case (org-element-type destination)
	  ;; ID link points to an external file.
	  (plain-text
	   (let ((fragment (concat "ID-" path))
		 ;; Treat links to ".org" files as ".html", if needed.
		 (path (funcall link-org-files-as-html-maybe
				destination info)))
	     (format "<a href=\"%s#%s\"%s>%s</a>"
		     path fragment attributes (or desc destination))))
	  ;; Fuzzy link points nowhere.
	  ((nil)
	   (format "<i>%s</i>"
		   (or desc
		       (org-export-data
			(org-element-property :raw-link link) info))))
	  ;; Link points to a headline.
	  (headline
	   (let ((href
		  ;; What href to use?
		  (cond
		   ;; Case 1: Headline is linked via it's CUSTOM_ID
		   ;; property.  Use CUSTOM_ID.
		   ((string= type "custom-id")
		    (org-element-property :CUSTOM_ID destination))
		   ;; Case 2: Headline is linked via it's ID property
		   ;; or through other means.  Use the default href.
		   ((member type '("id" "fuzzy"))
		    (format "sec-%s"
			    (mapconcat 'number-to-string
				       (org-export-get-headline-number
					destination info) "-")))
		   (t (error "Shouldn't reach here"))))
		 ;; What description to use?
		 (desc
		  ;; Case 1: Headline is numbered and LINK has no
		  ;; description.  Display section number.
		  (if (and (org-export-numbered-headline-p destination info)
			   (not desc))
		      (mapconcat 'number-to-string
				 (org-export-get-headline-number
				  destination info) ".")
		    ;; Case 2: Either the headline is un-numbered or
		    ;; LINK has a custom description.  Display LINK's
		    ;; description or headline's title.
		    (or desc (org-export-data (org-element-property
					       :title destination) info)))))
	     (format "<a href=\"#%s\"%s>%s</a>"
		     (org-export-solidify-link-text href) attributes desc)))
	  ;; Fuzzy link points to a target or an element.
	  (t
	   (let* ((path (org-export-solidify-link-text path))
		  (org-html-standalone-image-predicate 'org-html--has-caption-p)
		  (number (cond
			   (desc nil)
			   ((org-html-standalone-image-p destination info)
			    (org-export-get-ordinal
			     (org-element-map destination 'link
			       'identity info t)
			     info 'link 'org-html-standalone-image-p))
			   (t (org-export-get-ordinal
			       destination info nil 'org-html--has-caption-p))))
		  (desc (cond (desc)
			      ((not number) "No description for this link")
			      ((numberp number) (number-to-string number))
			      (t (mapconcat 'number-to-string number ".")))))
	     (format "<a href=\"#%s\"%s>%s</a>" path attributes desc))))))
     ;; Coderef: replace link with the reference name or the
     ;; equivalent line number.
     ((string= type "coderef")
      (let ((fragment (concat "coderef-" path)))
	(format "<a href=\"#%s\"%s%s>%s</a>"
		fragment
		(org-trim
		 (format (concat "class=\"coderef\""
				 " onmouseover=\"CodeHighlightOn(this, '%s');\""
				 " onmouseout=\"CodeHighlightOff(this, '%s');\"")
			 fragment fragment))
		attributes
		(format (org-export-get-coderef-format path desc)
			(org-export-resolve-coderef path info)))))
     ;; File: links to upload to the blog
     ((string= type "file")
      ;; Add blog allowed links to org-blog-files-to-upload list.
      (dolist (upload-type org-blog-upload-filetypes html-link)
        (let ((string-to-match (concat "." upload-type)))
          (message "upload type: %s \n" upload-type)
          (message "condition1: %s\n" (> (length raw-path)  (length string-to-match)))
          (message "string to match: %s\n" string-to-match)
          (message "substring: %s \n" (substring raw-path
                                         (- (length string-to-match))))
          (when (and (> (length raw-path)  (length string-to-match))
                     (string= string-to-match
                              (substring raw-path
                                         (- (length string-to-match)))))
            (message "upload: match!\n")
            (setq html-link
                  (concat "<a href=\""
                          raw-path
                          "\">"
                          desc
                          "</a>")))))
      (cdar (add-to-list 'org-blog-files-to-upload 
                         `(,raw-path . ,html-link)))
      (format "%s" html-link))
     ;; Link type is handled by a special function.
     ((functionp (setq protocol (nth 2 (assoc type org-link-protocols))))
      (funcall protocol (org-link-unescape path) desc 'html))
     ;; External link with a description part.
     ((and path desc) (format "<a href=\"%s\"%s>%s</a>" path attributes desc))
     ;; External link without a description part.
     (path (format "<a href=\"%s\"%s>%s</a>" path attributes path))
     ;; No path, only description.  Try to do something useful.
     (t (format "<i>%s</i>" desc)))))

;;;; Keyword

(defun org-blog-keyword (keyword contents info)
  "Transcode a KEYWORD element from Org to HTML.
CONTENTS is nil.  INFO is a plist holding contextual information."
  (let ((key (org-element-property :key keyword))
	(value (org-element-property :value keyword)))

    (cond ((string= key "BLOG")  value)
          ((string= key "BLOG_MORE") "<!--more-->")
          ((string= key "BLOG_DOC_LINK")
               (let* ((first-blank (string-match " " value))
                      (doctype (substring value 0 first-blank))
                      (desc (substring value (1+ first-blank)))
                      (raw-path (concat (substring
                                         buffer-file-name 0 -3)
                                        doctype))
                      (html-link (concat "<a href=\""
                                         raw-path
                                         "\">"
                                         desc
                                         "</a>")))
                 (add-to-list 'org-blog-files-to-upload 
                              `(,raw-path . ,html-link))
                 (format "%s" html-link)))
          (t (org-html-keyword keyword contents info)))))
  
;;;; Src Block

(defun org-blog-src-block (src-block contents info)
  "Transcode a SRC-BLOCK element from Org to HTML.
CONTENTS holds the contents of the item.  INFO is a plist holding
contextual information."
  ;; NOTE; a set label disturbs wp-syntax rendering.
  ;; CHECK for syntax highlighter
  (if (org-export-read-attribute :attr_html src-block :textarea)
      (org-html--textarea-block src-block)
    (let* ((highlighter (or (plist-get info :blog-syntax-highlighter)
                            "org-mode"))
           (hlall (assoc highlighter org-blog-syntax-highlighter-alist))
           (hl (cdr hlall))
           (lang (or (cdr (assoc (org-element-property :language src-block)
                                 (nth 7 hl)))
                     (car (member (org-element-property :language src-block)
                                  (nth 6 hl)))
                     (nth 5 hl)))
	  (caption (org-export-get-caption src-block))
	  (code (if (equal "org-mode" (car hlall))
                    (org-html-format-code src-block info)
                  (car (org-export-unravel-code src-block))))
	  (label (let ((lbl (org-element-property :name src-block)))
		   (if (not lbl) ""
		     (format " id=\"%s\""
			     (org-export-solidify-link-text lbl)))))
          (attributes (org-export-read-attribute :attr_blog src-block)))
      ;; (eq lang nil) should only occur with invalid highlighters
      (if (eq lang nil)
          (format "<pre class=\"example\"%s>\n%s</pre>" label code)
	(format
	 "<div class=\"org-src-container\">\n%s%s\n</div>"
	 (if (not caption) ""
	   (format "<label class=\"org-src-name\">%s</label>"
		   (org-export-data caption info)))
         (format
          (concat
           "\n"
           (nth 0 hl) (nth 2 hl)
           " "
           (nth 4 hl)
           "=\""
           ;; org-mode uses src class and src- prefix in source
           ;; block class names
           (if (and (string= highlighter "org-mode")
                    (not (string= lang "example")))
               "src src-")
           "%s\""
           ;; line numbers
           (let* ((number-lines (org-element-property :number-lines src-block))
                  (firstline (case number-lines
                               (continued (org-export-get-loc src-block info))
                               (new (or (plist-get attributes :firstline)
                                        1)))))
             (cond ((not firstline) (and (nth 9 hl)
                                         (format " %s" (nth 9 hl))))
                   (firstline (and (nth 10 hl)
                                   (format " %s=\"%s\""
                                           (nth 10 hl)
                                           firstline)))))
           (let ((highlight (plist-get attributes :highlight)))
             (and highlight
                  (format " %s=\"%s\"" (nth 11 hl) highlight)))
           ;; source title / url
           (let ((src-title (plist-get attributes :title)))
             (and src-title
                  (format " %s=%s" (nth 12 hl) src-title)))
           "%s"
           (nth 1 hl) ;; end of beginning tag
           "%s"
           (nth 0 hl) (nth 3 hl) (nth 2 hl) (nth 1 hl))
          lang
          ;; wp-syntax doesn't like foreign attributes in its <pre> tags
          (if (string= highlighter "wp-syntax")
              ""
            label)
          code))))))


;;; helper functions for export
(defun org-blog-wp-call (blog-access api-component &rest args)
  (apply #'xml-rpc-method-call
         (cdr (assoc :xmlrpc-url blog-access))
         api-component
         (cdr (assoc :blog-id blog-access))
         (cdr (assoc :username blog-access))
         (cdr (assoc :password blog-access))
         args))

(defun org-blog-get-blog-project-from-filename (filename)
  "Return the blog project that FILENAME belongs to."
  ; copied from org-publish
  (let* ((filename-full-path  (expand-file-name filename))
         (filename (file-name-nondirectory filename-full-path))
        blog-project)
    (dolist (prj org-blog-project-alist)
      (let ((b (expand-file-name (file-name-as-directory
                                  (plist-get (cdr prj) :base-directory)))))
        (when (string= filename-full-path
                            (expand-file-name filename b))
          (setq blog-project prj))))
    blog-project))


;;If you got options in MY FILE inthe form of
;;#+OPTION_NAME: a, b, two words, something else
;;#+OPTION_NAME: and, comma, at end,
;;#+OPTION_NAME: for, example
;;
;;
;;(:option-name is the KEYWORD in the options alist, cf. ox.el)
;;
;;you will get them now as
;;'( \"a\" \"b\" \"two words\" \"something else\" \"and\" \"comma\" \"at end\" \"for " "example").


(defun org-blog-taxonomy-terms-as-list (taxonomy ext-plist)
  "Fetch TAXONOMY (tags or categories) from FILE as a list"
  (mapcar 'org-trim
          (split-string
           (replace-regexp-in-string ", *" ","
                                     (or
                                      (plist-get ext-plist taxonomy)
                                      ""))
           "[,\n]"
           t)))


(defun org-blog-fetch-taxonomy-terms (blog-access taxonomy)
  "Fetches all terms in a TAXONOMY from blog.

TAXONOMY is  e.g. \"post_tag\" or \"category\""
  (mapcar (lambda (term)
            (cdr (assoc "name" term)))
          (org-blog-wp-call blog-access "wp.getTerms" taxonomy)))


(defun org-blog-create-taxonomy-term-list (blog-access taxonomy term-list confirm-p)
  "Creates a list of terms for TAXONOMY using TERM-LIST.

TAXONOMY can be either \"post_tag\" org \"category\".

Returns a alist '((taxonomy . term1) (taxonomy . term2))
for use in the wp.newPost and wp.editPost XML-RPC calls."
  (let* ((existing-terms (org-blog-fetch-taxonomy-terms blog-access taxonomy))
         (taxinfo (assoc taxonomy
                         '(("post_tag" "Tag")
                           ("category" "Category")))))

    (let ((terms
           (mapcar (lambda (term)
                     (let ((term-to-use nil))
                       (dolist (blog-term existing-terms)
                         (when (string= (downcase term)
                                        (downcase blog-term))
                           (setq term-to-use blog-term)))
                       (or term-to-use
                           (if confirm-p
                               (and (y-or-n-p
                                     (format "%s `%s 'not known to blog.  Add it? "
                                             (second taxinfo)
                                             term))
                                    term)
                             term))))
                   term-list)))
      (when terms (remove nil `(,taxonomy . ,terms))))))


(defun org-blog-post-exists-p (blog-access post-id)
  (let ((post-id-exists t))
    (condition-case err
        (org-blog-wp-call blog-access "wp.getPost"  post-id '("post_id"))
      (error err
             (equal (car (cdr err))
                    "XML-RPC fault `Invalid post ID.'")
             (setq post-id-exists nil)))
    post-id-exists))


(defun org-blog-upload-images (blog-access images)
  "Upload IMAGES to blog using BLOG-ACCESS."
  (mapc
   (lambda (image)
     (goto-char (point-max))
     (when (search-backward (cdr image) nil t)
       (search-forward (concat "src=\""
                                (car image)
                                "\"") nil t)
       (search-backward (car image) nil t)
       (delete-char (length (car image)))
       (insert
        (cdr
         (assoc
          "url"
          (let ((xml-rpc-allow-unicode-string nil)
                (raw-path (car image)))
            (with-temp-buffer
              (insert-file-contents-literally raw-path)
              (org-blog-wp-call blog-access "wp.uploadFile"
                                `(("name" .
                                   ,(file-name-nondirectory raw-path))
                                  ("type " .
                                   ,(mailcap-extension-to-mime
                                     (file-name-extension raw-path)))
                                  ("bits" . ,(buffer-string))
                                  ("overwrite" . 1))))))))))
   images))

(defun org-blog-upload-files (blog-access files)
  "Upload IMAGES to blog using BLOG-ACCESS."
  (mapc
   (lambda (file)
     (goto-char (point-max))
     (when (search-backward (cdr file) nil t)
       (search-forward (concat "href=\""
                                (car file)
                                "\"") nil t)
       (search-backward (car file) nil t)
       (delete-char (length (car file)))
       (insert
        (cdr
         (assoc
          "url"
          (let ((xml-rpc-allow-unicode-string nil)
                (raw-path (car file)))
            (with-temp-buffer
              (insert-file-contents-literally raw-path)
              (org-blog-wp-call blog-access "wp.uploadFile"
                                `(("name" .
                                   ,(file-name-nondirectory raw-path))
                                  ("type " .
                                   ,(mailcap-extension-to-mime
                                     (file-name-extension raw-path)))
                                  ("bits" . ,(buffer-string))
                                  ("overwrite" . 1))))))))))
   files))


(defun org-blog-inner-template (contents info)
  "Return body of document string after blog HTML conversion.
CONTENTS is the transcoded contents string.  INFO is a plist
holding export options."
  (concat
   ;; Table of contents.
   (let ((depth (plist-get info :with-toc)))
     (when depth (org-html-toc depth info)))
   ;; Document contents.
   contents
   ;; Footnotes section.
   (org-html-footnote-section info)))

(defun org-blog-template (contents info)
  "Return complete document string after blog HTML conversion.
CONTENTS is the transcoded contents string.  INFO is a plist
holding export options.

This function is just calling org-blog-inner-template, as
for a wordpress blog only the document body is needed.
"
  (org-blog-inner-template contents info))



;;; End-user functions

;;;###autoload
(defun org-blog-export-as-html
  (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to an blog HTML buffer.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting buffer should be accessible
through the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"<body>\" and \"</body>\" tags.

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Export is done in a buffer named \"*Org BLOG Export*\", which
will be displayed when `org-export-show-temporary-export-buffer'
is non-nil."
  (interactive)
  (org-export-to-buffer 'blog "*Org Blog Export*"
   async subtreep visible-only body-only ext-plist
   (lambda () (set-auto-mode t))))

;;;###autoload
(defun org-blog-convert-region-to-html ()
  "Assume the current region has org-mode syntax, and convert it to blog HTML.
This can be used in any buffer.  For example, you can write an
itemized list in org-mode syntax in an blog HTML buffer and use this
command to convert it."
  (interactive)
  (org-export-replace-region-by 'blog))

;;;###autoload
(defun org-blog-export-to-html
  (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to a blog HTML file.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through
the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"<body>\" and \"</body>\" tags.

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Return output file's name."
  (interactive)
  (let* ((extension (concat "." org-html-extension))
	 (file (org-export-output-file-name extension subtreep))
	 (org-export-coding-system org-html-coding-system))
    (org-export-to-file 'blog file
                        async subtreep visible-only body-only ext-plist)))

;;;###autoload
(defun org-blog-export-to-blog
  (draft-or-publish-p &optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to an blog HTML buffer."
  (interactive)
  ;; fetch blog project, if available
  (let* ((project (org-blog-get-blog-project-from-filename (buffer-file-name)))
         (project-name (car project))
         (project-plist (cdr project))
         (post-environment (org-combine-plists
                            project-plist
                            (org-export-get-environment 'blog subtreep ext-plist)))
         (username (or (plist-get post-environment :blog-username)
                       (read-string (message "Enter user name for blog%s: "
                                             (if project-name
                                                 (concat " " project-name)
                                               "")))))
         (blog-access
          `((:xmlrpc-url
             . 
             ,(let ((url  (plist-get post-environment :blog-url)))
                (concat url
                        (and (not (string= "/" (substring url -1)))
                             "/")
                        "xmlrpc.php")))
            (:blog-id . ,(plist-get post-environment :blog-id))
            (:username . ,username)
            (:password
             .
             ,(or (plist-get post-environment :blog-password)
                  (read-passwd
                   (message "Enter password for user %s on blog%s: "
                            username
                            (if project-name
                                (concat " " project-name)
                              "")))))))
         (source-buffer (buffer-name))
         (post-content)
         (new-post-id))
    ;; org-blog-export-as-html does it's own subtree narrowing....
    (setq org-blog-image-list ())  ;; will be uploaded right before the post
    (setq org-blog-files-to-upload ())  ;; ditto
    (org-blog-export-as-html async subtreep visible-only body-only ext-plist)
    ;; upload images and files (and change paths in HTML)
    (org-blog-upload-images blog-access org-blog-image-list)
    (org-blog-upload-files blog-access org-blog-files-to-upload)

    (setq post-content (buffer-string))
    (set-buffer source-buffer)
    (let* ((post-id (string-to-number
                     (org-element-interpret-data
                      (plist-get post-environment :blog-post-id))))
           (post-title (org-element-interpret-data
                        (plist-get post-environment :title)))
           (publish-datetime (or (org-element-interpret-data
                                  (plist-get post-environment :blog-publish-datetime))
                                 (org-entry-get (point) "SCHEDULED")
                                 (org-entry-get (point) "DEADLINE")
                                 (org-entry-get (point) "TIMESTAMP")
                                 (org-entry-get (point) "TIMESTAMP_IA")))
           ;; TODO:
           (timezone (or (plist-get post-environment :blog-timezone)
                         0)) ;; fallback GMT
           (use-tags-as-categories (plist-get post-environment
                                              :blog-use-tags-as-categories))
           (tag-list (org-blog-create-taxonomy-term-list
                      blog-access
                      "post_tag"
                      (let ((partial-list
                             (org-blog-taxonomy-terms-as-list
                              :blog-tags
                              post-environment)))
                        (mapc (lambda (elt) (add-to-list 'partial-list elt))
                              (org-get-tags-at (point)))
                        partial-list)
                      (plist-get post-environment
                                 :blog-confirm-new-tags)))
           (category-list (if use-tags-as-categories
                              tag-list
                            (org-blog-create-taxonomy-term-list
                             blog-access "category"
                             (org-blog-taxonomy-terms-as-list :blog-categories
                                                              post-environment)
                             (plist-get post-environment :blog-confirm-new-categories))))
           (use-tags-as-categories
            (plist-get post-environment :blog-use-tags-as-categories))
           (user-role
            (cadr (assoc "roles"
                         (org-blog-wp-call blog-access "wp.getProfile" '("roles")))))
           ;; most roles may draft, contributor may submit
           ;; (aka. pending) instead of post; author and
           ;; administrator may post
           (post-status (cond ((equal draft-or-publish-p "draft") "draft")
                              ((equal "contributor" user-role) "pending")
                              ((and (not (string= "" publish-datetime))
                                    (or (equal "author" user-role)
                                        (equal "administrator" user-role)))
                               "future")
                              ((equal "author" user-role) "publish")
                              ((equal "administrator" user-role) "publish")))
           ;; the post structure list only likes (key . value) elements,
           ;; so a careful removel of nil's is in order.
           (post-struct
            (remove nil
                    `(("post_title" . ,post-title)
                      ("post_type" . ,(org-element-interpret-data
                                       (plist-get post-environment :blog-post-type)))
                      ("post_status" . ,post-status)
                      ,(when (string= post-status "future")
                         `("post_date" . (:datetime
                                          ,(apply 'encode-time
                                                  (org-parse-time-string
                                                   publish-datetime)))))
                      ("post_content" . ,post-content)
                      ,(when (or tag-list
                                 category-list)
                         `("terms_names"
                           .
                           ,(append (when (and (not use-tags-as-categories)
                                               tag-list)
                                      `(,tag-list))
                                    (when category-list
                                      `(,category-list)))))))))
      ; (print post-struct)
      (message "Post-ID: %d" post-id)
      (if (/= 0 post-id)
          (org-blog-wp-call blog-access "wp.editPost" post-id post-struct)
        (setq new-post-id
              (org-blog-wp-call blog-access "wp.newPost" post-struct)))
      (when (= post-id 0)
        (if subtreep
            (org-set-property "EXPORT_BLOG_POST_ID" new-post-id)
          (progn
            (goto-char (point-min))
            (eq (following-char) 35)
            (forward-line)
            (insert (concat "#+BLOG_POST_ID: " new-post-id "\n"))))
        (save-buffer))
      )))


;;;###autoload
(defun org-blog-export-to-blog-as-draft
   (&optional async subtreep visible-only body-only ext-plist)
   (org-blog-export-to-blog "draft" async subtreep visible-only body-only ext-plist))

;;;###autoload
(defun org-blog-export-to-blog-as-publish
  (&optional async subtreep visible-only body-only ext-plist)
  (org-blog-export-to-blog "publish" async subtreep visible-only body-only ext-plist))

;;;###autoload
(defun org-blog-publish-to-html (plist filename pub-dir)
  "Publish an org file to blog HTML.

FILENAME is the filename of the Org file to be published.  PLIST
is the property list for the given project.  PUB-DIR is the
publishing directory.

Return output file name."
  (org-publish-org-to 'blog filename
		      (concat "." (or (plist-get plist :html-extension)
				      org-html-extension "html"))
		      plist pub-dir))


(provide 'ox-blog)

;; Local variables:
;; generated-autoload-file: "org-loaddefs.el"
;; End:

;;; ox-blog.el ends here
