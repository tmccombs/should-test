;;;;; SHOULD-TEST core: package definition and main functions
;;;;; (c) 2013 Vsevolod Dyomkin

(cl:defpackage #:should-test
  (:nicknames #:st)
  (:use #:common-lisp #:rutil)
  (:export #:deftest
           #:should
           #:should-check
           #:should-format
           #:should-test-error
           #:test

           #:*test-output*
           #:*verbose*))

(in-package #:should-test)
(named-readtables:in-readtable rutils-readtable)


(defvar *test-output* *standard-output*
  "Stream to print test results.")

(defparameter *verbose* t)

(define-condition should-test-error (simple-error) ())


(defmacro deftest (name () &body body)
  "Define a NAMEd test which is a function
   that treats each form in its body as an assertion to be checked
   and prints some information to the output.
   The result of this function is a boolean indicating
   if any of the assertions has failed.
   In case of failure second value is a list of failure descriptions,
   returned from assertions,
   and the third value is a list of uncaught errors if any"
  (with-gensyms (rez failed erred e)
    `(progn
       (when (get ',name 'test)
         (warn "Redefining test ~A" ',name))
       (setf (get ',name 'test)
             (lambda ()
               (format *test-output* "Test ~A: " ',name)
               (let* ((,rez (list
                              ,@(mapcar (lambda (assertion)
                                          `(handler-case
                                               (multiple-value-list ,assertion)
                                             (error (,e) (list ,e))))
                                        body)))
                      (,failed (remove-if-not #'null ,rez :key #'car))
                      (,erred (remove-if #`(member % '(nil t)) ,rez :key #'car)))
                 (if (or ,failed ,erred)
                     (progn
                       (format *test-output* "  FAILED~%")
                       (values nil
                               ,failed
                               ,erred))
                     (progn
                       (format *test-output* "  OK~%")
                       t))))))))

(defun test (&key (package *package*) test)
  "Run a scpecific TEST or all tests defined in PACKAGE (defaults to current).

   Returns T if all tests pass or 3 values:

   - NIL
   - a hash-table of failed tests with their failed assertions' lists
   - a hash-table of tests that have signalled uncaught errors with these errors"
  (if test
      (if-it (get test 'test)
             (funcall it)
             (error 'should-test-error "No test defined for ~A" test))
      (let ((failures #{}) (errors #{}))
        (do-symbols (sym package)
          (when-it (get sym 'test)
            (mv-bind (success? failed erred) (funcall it)
              (unless success?
                (when failed
                  (set# sym failures failed))
                (when erred
                  (set# sym errors erred))))))
        (or (zerop (+ (hash-table-count failures)
                      (hash-table-count errors)))
            (values nil
                    failures
                    errors)))))

(defmacro should (key test &rest expected-and-testee)
  "Define an individual test from:

   - a comparison TEST
   - EXPECTED values
   - an operation that needs to be tested (TESTEE)

   KEY is used to determine, which kind of results processing is needed
   (implemented by generic function SHOULD-CHECK methods).
   The simplest key is BE that just checks for equality.
   Another pre-defined key is SIGNAL, which intercepts conditions."
  (with-gensyms (success? failed)
    (mv-bind (expected operation) (butlast2 expected-and-testee)
      `(mv-bind (,success? ,failed)
           (should-check ,(mkeyw key) ',test
                         (lambda () ,operation) ,@expected)
         (or ,success?
             (when *verbose*
               (format *test-output*
                       "~&~A FAIL~%expect:~{ ~A~}~%actual:~{ ~A~}~%"
                       ',operation
                       (mapcar #'should-format (list ,@expected))
                       (mklist (should-format ,failed))))
             (values nil
                     (list ',operation ',expected ,failed)))))))

(defgeneric should-check (key test fn &rest expected)
  (:documentation
   "Specific processing for SHOULD based on KEY.
    FN's output values are matched to EXPECTED values (if they are given).
    Up to 2 values are returned:

    - if the test passed (T or NIL)
    - in case of failure - actual result"))

(defmethod should-check ((key (eql :be)) test fn &rest expected)
  (let ((rez (multiple-value-list (funcall fn))))
    (or (every test rez (mklist expected))
        (values nil
                rez))))

(defmethod should-check ((key (eql :signal)) test fn &rest expected)
  (declare (ignore expected))
  (handler-case (progn (funcall fn)
                       (values nil
                               nil))
    (condition (c)
      (or (eql test (class-name (class-of c)))
          (values nil
                  c)))))

(defmethod should-check ((key (eql :print-to)) stream-sym fn &rest expected)
  (let ((original-value (symbol-value stream-sym)))
    (unwind-protect
         (progn (setf (symbol-value stream-sym)
                      (make-string-output-stream))
                (funcall fn)
                (let ((rez (get-output-stream-string (symbol-value stream-sym))))
                  (or (string= (first expected) rez)
                      (values nil
                              rez))))
      (setf (symbol-value stream-sym) original-value))))

(defgeneric should-format (obj)
  (:documentation "Format appropriately for test output.")
  (:method :around (obj)
    (let ((*print-length* 3)) (call-next-method)))
  (:method (obj)
    (fmt "~S" obj))
  (:method ((obj hash-table))
    (with-output-to-string (out) (print-ht obj out)))
  (:method ((obj list))
    (mapcar #'should-format obj)))