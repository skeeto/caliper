;;; caliper.el --- compute elisp object sizes -*- lexical-binding: t; -*-

;; This is free and unencumbered software released into the public domain.

;; Author: Christopher Wellons <wellons@nullprogram.com>
;; URL: https://github.com/skeeto/caliper
;; Package-Requires: ((predd "1.0.0"))

;;; Commentary:

;; This library provides exactly one function, `caliper-object-size'.
;; Give it any lisp object and it will deeply compute the total number
;; of bytes of memory consumed by that object (list, string, vector,
;; etc.). It could be used to optmize memory usage of an elisp
;; program.

;; It's not possible to get exact byte counts for complex built-in
;; types, such as hash-tables, buffers, and char-tables so only a
;; rough estimate is returned based on the elisp-accessible contents.

;; Requires the predicate dispatch `predd' package.

;;; Code:

(require 'cl-lib)
(require 'predd)

(defvar caliper--object-sizes
  (mapcar (lambda (kind) (cons (nth 0 kind) (nth 1 kind))) (garbage-collect))
  "List of lisp object sizes for the current host.")

(defvar caliper--seen-objects nil
  "To be bound dynamically during object size analysis.")

(defun caliper-kind-size (type)
  "Lookup a size in `caliper--object-sizes'."
  (cdr (assq type caliper--object-sizes)))

(defmacro caliper-check-seen (object &rest body)
  (declare (indent 1))
  `(let* ((caliper--seen-objects
           (or caliper--seen-objects (make-hash-table :test 'eq))))
     (or (gethash ,object caliper--seen-objects)
         (progn
           (setf (gethash ,object caliper--seen-objects) 0)
           ,@body))))

(predd-defmulti caliper-object-size #'type-of
  "Return the total number of bytes used by OBJECT.

For complex built-in types (hash-table, buffer, char-table),
return values are only a rough estimate, as indicated by a float
return type.")

(predd-defmethod caliper-object-size :default (object)
  (caliper-check-seen object
    (float (caliper-kind-size 'miscs))))

(predd-defmethod caliper-object-size 'integer (_)
  0) ; integers are tagged, stored within pointers

(predd-defmethod caliper-object-size 'float (object)
  (caliper-check-seen object
    (caliper-kind-size 'floats)))

(predd-defmethod caliper-object-size 'string (object)
  (caliper-check-seen object
    (+ (caliper-kind-size 'strings)
       (* (caliper-kind-size 'string-bytes) (string-bytes object)))))

(predd-defmethod caliper-object-size 'vector (object)
  (caliper-check-seen object
    (+ (caliper-kind-size 'vectors)
       (* (caliper-kind-size 'vector-slots) (length object))
       (cl-reduce #'+ (cl-mapcar #'caliper-object-size object)))))

(predd-defmethod caliper-object-size 'cons (object)
  (caliper-check-seen object
    (+ (caliper-kind-size 'conses)
       (caliper-object-size (car object))
       (caliper-object-size (cdr object)))))

(predd-defmethod caliper-object-size 'symbol (object)
  (caliper-check-seen object
    (+ (caliper-kind-size 'symbols)
       (caliper-object-size (symbol-plist object))
       (caliper-object-size (symbol-name object)))))

(predd-defmethod caliper-object-size 'buffer (object)
  (caliper-check-seen object
    (float
     (with-current-buffer object
       (save-restriction
         (widen)
         (+ (position-bytes (point-max))
            (- (position-bytes (point-min)))
            (gap-size)
            ;; warning is Emacs bug#15326
            (cl-loop for (_ . value) in (buffer-local-variables)
                     sum (caliper-object-size value))))))))

(predd-defmethod caliper-object-size 'hash-table (object)
  (caliper-check-seen object
    (float
     (+ (* 18 (caliper-kind-size 'vector-slots)) ; estimate from lisp.h
        (* (hash-table-size object) (caliper-kind-size 'vector-slots))
        (cl-loop for key being the hash-keys of object
                 using (hash-value value)
                 sum (caliper-object-size key)
                 sum (caliper-object-size value))))))

(predd-defmethod caliper-object-size 'char-table (object)
  (caliper-check-seen object
    (let ((slot-size (caliper-kind-size 'vector-slots)))
      (float
       (+ (* 135 slot-size) ; estimate from lisp.h
          (let ((count 0))
            (map-char-table (lambda (_ v)
                              (cl-incf count (caliper-object-size v)))
                            object)
            count)
          (let ((parent (char-table-parent object)))
            (if parent
                (caliper-object-size parent)
              0)))))))

(predd-defmethod caliper-object-size 'bool-vector (object)
  (caliper-check-seen object
    (float
     (+ (* 3 (caliper-kind-size 'vector-slots)) ; estimate from lisp.h
        (ceiling (length object) 8)))))

(predd-defmethod caliper-object-size 'frame (_)
  (error "Cannot compute the size of a frame!"))

(predd-defmethod caliper-object-size 'subr (_)
  (error "Cannot compute the size of a built-in function!"))

(predd-derive 'compiled-function 'vector)

(provide 'caliper)

;;; caliper.el ends here
